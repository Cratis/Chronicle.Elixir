# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.Handler do
  @moduledoc false

  # GenServer that maintains a bidirectional gRPC stream with Chronicle for a
  # single reactor module. On start, it waits for the connection to be ready,
  # sends a registration message, then receives event batches and dispatches
  # them to the reactor module's handle/2 callback.
  #
  # If the stream fails, the handler reconnects with exponential backoff.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.Observation.Reactors.{
    Reactors,
    ReactorMessage,
    ReactorDefinition,
    RegisterReactor,
    ReactorResult,
    EventTypeWithKeyExpression,
    ObserverFilters
  }

  alias Cratis.Chronicle.Contracts.Observation.Reactors.EventType, as: ProtoEventType
  alias Cratis.Chronicle.Contracts.Observation.Reactors.OneOf_RegisterReactor_ReactorResult, as: OneOf

  @reconnect_base_delay 1_000
  @reconnect_max_delay 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    event_type_modules = module.__chronicle_reactor__(:handles)

    event_type_map =
      Map.new(event_type_modules, fn et_module ->
        {et_module.__chronicle_event_type__(:id), et_module}
      end)

    state = %{
      module: module,
      connection: Keyword.fetch!(opts, :connection),
      session: Keyword.get(opts, :session),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.fetch!(opts, :namespace),
      event_type_map: event_type_map,
      stream: nil,
      receiver_task: nil,
      reconnect_attempt: 0,
      reconnect_timer: nil
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    state = %{state | reconnect_timer: nil}

    with :ok <- wait_for_session(state),
         {:ok, channel} <- Connection.channel(state.connection),
         {:ok, new_state} <- start_stream(channel, state) do
      {:noreply, new_state}
    else
      {:error, :session_timeout} ->
        Logger.warning("Reactor #{state.module} timed out waiting for session, retrying...")
        {:noreply, schedule_reconnect(state)}

      {:error, _reason} ->
        {:noreply, schedule_reconnect(state)}

      :error ->
        {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:event_batch, events_to_observe}, state) do
    partition = Map.get(events_to_observe, :Partition, "")
    events = Map.get(events_to_observe, :Events, [])

    {observation_state, exception_messages, stack_trace} =
      Enum.reduce_while(events, {:success, [], ""}, fn appended_event, _acc ->
        case dispatch_event(state, appended_event) do
          :ok -> {:cont, {:success, [], ""}}
          {:error, reason} -> {:halt, {:failed, [inspect(reason)], format_stack_trace(reason)}}
        end
      end)

    last_seq =
      case List.last(events) do
        nil -> 0
        event -> Map.get(Map.get(event, :Context, %{}), :SequenceNumber, 0)
      end

    result = struct(ReactorMessage,
      Content: struct(OneOf,
        Value1: struct(ReactorResult,
          Partition: partition,
          State: encode_observation_state(observation_state),
          LastSuccessfulObservation: last_seq,
          ExceptionMessages: exception_messages,
          ExceptionStackTrace: stack_trace
        )
      )
    )

    GRPC.Stub.send_request(state.stream, result)
    {:noreply, state}
  end

  def handle_info({:stream_down, reason}, state) do
    Logger.warning("Reactor #{state.module} stream disconnected: #{inspect(reason)}")
    cleanup_stream(state)
    {:noreply, schedule_reconnect(%{state | stream: nil, receiver_task: nil})}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{receiver_task: %Task{pid: pid}} = state) do
    Logger.warning("Reactor #{state.module} receiver task exited: #{inspect(reason)}")
    {:noreply, schedule_reconnect(%{state | stream: nil, receiver_task: nil})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp wait_for_session(%{session: nil}), do: :ok

  defp wait_for_session(%{session: session_name}) do
    case Chronicle.Session.wait_until_ready(session_name, 10_000) do
      :ok -> :ok
      {:error, :timeout} -> {:error, :session_timeout}
    end
  end

  defp start_stream(channel, state) do
    try do
      stream = Reactors.Stub.observe(channel)
      registration = build_registration(state)
      GRPC.Stub.send_request(stream, registration)

      handler = self()
      task = Task.async(fn -> receive_loop(handler, stream) end)

      {:ok, %{state | stream: stream, receiver_task: task, reconnect_attempt: 0}}
    rescue
      e -> {:error, e}
    end
  end

  defp receive_loop(handler, stream) do
    case GRPC.Stub.recv(stream) do
      {:ok, reply_stream} ->
        Enum.each(reply_stream, fn
          {:ok, events_to_observe} ->
            send(handler, {:event_batch, events_to_observe})

          {:error, reason} ->
            send(handler, {:stream_down, reason})
        end)

      {:error, reason} ->
        send(handler, {:stream_down, reason})
    end
  end

  defp build_registration(state) do
    event_types =
      Enum.map(state.event_type_map, fn {id, module} ->
        struct(EventTypeWithKeyExpression,
          EventType: struct(ProtoEventType,
            Id: id,
            Generation: module.__chronicle_event_type__(:generation)
          ),
          Key: "$eventSourceId"
        )
      end)

    reactor_id = state.module.__chronicle_reactor__(:id)
    conn_id = if state.session, do: Chronicle.Session.connection_id(state.session), else: generate_connection_id()

    struct(ReactorMessage,
      Content: struct(OneOf,
        Value0: struct(RegisterReactor,
          ConnectionId: conn_id,
          EventStore: state.event_store,
          Namespace: state.namespace,
          Reactor: struct(ReactorDefinition,
            ReactorId: reactor_id,
            EventSequenceId: "event-log",
            EventTypes: event_types,
            IsReplayable: true,
            Tags: [],
            Filters: struct(ObserverFilters)
          )
        )
      )
    )
  end

  defp dispatch_event(state, appended_event) do
    context = Map.get(appended_event, :Context, %{})
    event_type = Map.get(context, :EventType, %{})
    event_type_id = Map.get(event_type, :Id, "")

    case Map.get(state.event_type_map, event_type_id) do
      nil ->
        :ok

      event_module ->
        ctx = build_context(context)
        content = Map.get(appended_event, :Content, "")

        case decode_event(event_module, content) do
          {:ok, event} ->
            try do
              state.module.handle(event, ctx)
            rescue
              e -> {:error, e}
            end

          {:error, reason} ->
            Logger.warning("Failed to decode event #{event_type_id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp decode_event(event_module, json_content) do
    case Jason.decode(json_content) do
      {:ok, attrs} ->
        fields =
          attrs
          |> Enum.flat_map(fn {key, val} ->
            snake_key = pascal_to_snake(key)

            try do
              [{String.to_existing_atom(snake_key), val}]
            rescue
              ArgumentError -> []
            end
          end)
          |> Enum.filter(fn {key, _} -> Map.has_key?(event_module.__struct__(), key) end)

        {:ok, struct(event_module, fields)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pascal_to_snake(str) do
    str
    |> String.replace(~r/(?<=[a-z0-9])([A-Z])/, "_\\1")
    |> String.downcase()
  end

  defp build_context(ctx) do
    occurred = Map.get(ctx, :Occurred)

    %{
      event_source_id: Map.get(ctx, :EventSourceId, ""),
      sequence_number: Map.get(ctx, :SequenceNumber, 0),
      occurred: occurred && Map.get(occurred, :Value),
      event_store: Map.get(ctx, :EventStore, ""),
      namespace: Map.get(ctx, :Namespace, "")
    }
  end

  defp schedule_reconnect(state) do
    delay =
      @reconnect_base_delay
      |> Kernel.*(Integer.pow(2, state.reconnect_attempt))
      |> min(@reconnect_max_delay)

    timer = Process.send_after(self(), :connect, delay)
    %{state | reconnect_attempt: state.reconnect_attempt + 1, reconnect_timer: timer}
  end

  defp cleanup_stream(%{stream: nil}), do: :ok

  defp cleanup_stream(%{stream: stream}) do
    try do
      GRPC.Stub.end_stream(stream)
    rescue
      _ -> :ok
    end
  end

  # ObservationState enum: Success = 1, Failed = 2
  defp encode_observation_state(:success), do: 1
  defp encode_observation_state(:failed), do: 2

  defp format_stack_trace(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_stack_trace(reason), do: inspect(reason)

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
