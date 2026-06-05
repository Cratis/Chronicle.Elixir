# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.Handler do
  @moduledoc false

  # GenServer that maintains a bidirectional gRPC stream with Chronicle for a
  # single reducer module. Chronicle sends ReduceOperationMessage batches
  # containing the current read model state and the events to apply. The
  # handler calls the reducer's reduce/3 callback for each event and returns
  # the resulting read model JSON.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.{Connection, Lifecycle}

  alias Cratis.Chronicle.Contracts.Observation.Reducers.{
    Reducers,
    ReducerMessage,
    ReducerDefinition,
    RegisterReducer,
    ReducerResult,
    EventTypeWithKeyExpression,
    ObserverFilters,
    SinkDefinition
  }

  alias Cratis.Chronicle.Contracts.Observation.Reducers.EventType, as: ProtoEventType

  alias Cratis.Chronicle.Contracts.Observation.Reducers.OneOf_RegisterReducer_ReducerResult,
    as: OneOf

  alias Bcl.Guid, as: BclGuid

  # MongoDB sink type ID: "22202c41-2be1-4547-9c00-f0b1f797fd75"
  defp mongodb_sink_type_id, do: struct(BclGuid, lo: 0x45472BE122202C41, hi: 0x75FD97F7B1F0009C)

  # Stream-level reconnect delay (matches the C# client's per-stream retry).
  @stream_reconnect_delay 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    event_type_modules = module.__chronicle_reducer__(:handles)

    event_type_map =
      Map.new(event_type_modules, fn et_module ->
        {et_module.__chronicle_event_type__(:id), et_module}
      end)

    state = %{
      module: module,
      connection: Keyword.fetch!(opts, :connection),
      lifecycle: Keyword.get(opts, :lifecycle),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.fetch!(opts, :namespace),
      event_type_map: event_type_map,
      model_module: module.__chronicle_reducer__(:model),
      establish_fun: Keyword.get(opts, :establish_fun, &default_establish/2),
      connection_id: nil,
      stream: nil,
      receiver_task: nil,
      reconnect_timer: nil
    }

    if state.lifecycle, do: Lifecycle.subscribe(state.lifecycle)

    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, :registered, connection_id}, state) do
    # Base artifacts (incl. this reducer's read-model definition) are registered
    # server-side — only now is it safe to open the observation stream.
    state = teardown(%{state | connection_id: connection_id})
    {:noreply, establish(state)}
  end

  def handle_info({:chronicle_lifecycle, :connected, _connection_id}, state) do
    # Connected but not yet registered — registering here would race ahead of
    # the reducer's server-side definition. Wait for :registered.
    {:noreply, state}
  end

  def handle_info({:chronicle_lifecycle, :disconnected, _connection_id}, state) do
    {:noreply, teardown(state)}
  end

  def handle_info(:reopen, state) do
    state = %{state | reconnect_timer: nil}

    if registered?(state) do
      {:noreply, establish(teardown(state))}
    else
      # No longer in the registered phase; the next :registered will re-establish.
      {:noreply, state}
    end
  end

  def handle_info({:reduce_operation, reduce_op}, state) do
    partition = Map.get(reduce_op, :Partition, "")
    initial_state_json = Map.get(reduce_op, :InitialState, "")
    events = Map.get(reduce_op, :Events, [])

    initial_model = decode_model(state.model_module, initial_state_json)

    {final_state, observation_state, exception_messages, stack_trace} =
      Enum.reduce_while(events, {initial_model, :success, [], ""}, fn event, {model, _, _, _} ->
        case apply_reduce(state, event, model) do
          {:ok, new_model} ->
            {:cont, {new_model, :success, [], ""}}

          {:error, reason} ->
            {:halt, {model, :failed, [inspect(reason)], format_stack_trace(reason)}}
        end
      end)

    last_seq =
      case List.last(events) do
        nil -> 0
        event -> Map.get(Map.get(event, :Context, %{}), :SequenceNumber, 0)
      end

    read_model_json =
      case final_state do
        nil -> ""
        model -> model |> Map.from_struct() |> Jason.encode!()
      end

    result =
      struct(ReducerMessage,
        Content:
          struct(OneOf,
            Value1:
              struct(ReducerResult,
                Partition: partition,
                State: encode_observation_state(observation_state),
                LastSuccessfulObservation: last_seq,
                ExceptionMessages: exception_messages,
                ExceptionStackTrace: stack_trace,
                ReadModelState: read_model_json
              )
          )
      )

    GRPC.Stub.send_request(state.stream, result)
    {:noreply, state}
  end

  def handle_info({:stream_down, reason}, state) do
    Logger.warning("Reducer #{state.module} stream disconnected: #{inspect(reason)}")
    {:noreply, schedule_stream_reconnect(teardown(state))}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{receiver_task: %Task{pid: pid}} = state) do
    Logger.warning("Reducer #{state.module} receiver task exited: #{inspect(reason)}")
    {:noreply, schedule_stream_reconnect(%{state | stream: nil, receiver_task: nil})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Opens the observation stream for the current connection id, returning the
  # updated state. On failure it schedules a stream-level reconnect.
  defp establish(state) do
    case state.establish_fun.(state, state.connection_id) do
      {:ok, stream, task} ->
        %{state | stream: stream, receiver_task: task, reconnect_timer: nil}

      {:error, reason} ->
        Logger.warning("Reducer #{state.module} failed to register: #{inspect(reason)}")
        schedule_stream_reconnect(state)
    end
  end

  defp default_establish(state, connection_id) do
    case Connection.channel(state.connection) do
      {:ok, channel} ->
        stream = Reducers.Stub.observe(channel)
        registration = build_registration(state, connection_id)
        GRPC.Stub.send_request(stream, registration)

        handler = self()
        task = Task.async(fn -> receive_loop(handler, stream) end)
        {:ok, stream, task}

      {:error, _} = error ->
        error
    end
  rescue
    e -> {:error, e}
  end

  defp registered?(%{lifecycle: nil}), do: true
  defp registered?(%{lifecycle: lifecycle}), do: Lifecycle.phase(lifecycle) == :registered

  defp receive_loop(handler, stream) do
    case GRPC.Stub.recv(stream) do
      {:ok, reply_stream} ->
        Enum.each(reply_stream, fn
          {:ok, reduce_op} ->
            send(handler, {:reduce_operation, reduce_op})

          {:error, reason} ->
            send(handler, {:stream_down, reason})
        end)

      {:error, reason} ->
        send(handler, {:stream_down, reason})
    end
  end

  defp build_registration(state, conn_id) do
    event_types =
      Enum.map(state.event_type_map, fn {id, module} ->
        struct(EventTypeWithKeyExpression,
          EventType:
            struct(ProtoEventType,
              Id: id,
              Generation: module.__chronicle_event_type__(:generation)
            ),
          Key: "$eventSourceId"
        )
      end)

    reducer_id = state.module.__chronicle_reducer__(:id)
    model_id = state.model_module.__chronicle_read_model__(:id)

    struct(ReducerMessage,
      Content:
        struct(OneOf,
          Value0:
            struct(RegisterReducer,
              ConnectionId: conn_id,
              EventStore: state.event_store,
              Namespace: state.namespace,
              Reducer:
                struct(ReducerDefinition,
                  ReducerId: reducer_id,
                  EventSequenceId: "event-log",
                  EventTypes: event_types,
                  ReadModel: model_id,
                  IsActive: true,
                  Sink: struct(SinkDefinition, TypeId: mongodb_sink_type_id()),
                  Tags: [],
                  Filters: struct(ObserverFilters)
                )
            )
        )
    )
  end

  defp apply_reduce(state, appended_event, model) do
    context = Map.get(appended_event, :Context, %{})
    event_type = Map.get(context, :EventType, %{})
    event_type_id = Map.get(event_type, :Id, "")

    case Map.get(state.event_type_map, event_type_id) do
      nil ->
        {:ok, model}

      event_module ->
        ctx = build_context(context)
        content = Map.get(appended_event, :Content, "")

        case decode_event(event_module, content) do
          {:ok, event} ->
            try do
              {:ok, state.module.reduce(event, model, ctx)}
            rescue
              e -> {:error, e}
            end

          {:error, reason} ->
            Logger.warning("Failed to decode event #{event_type_id}: #{inspect(reason)}")
            {:ok, model}
        end
    end
  end

  defp decode_model(_module, ""), do: nil
  defp decode_model(_module, nil), do: nil

  defp decode_model(module, json) do
    case Jason.decode(json) do
      {:ok, attrs} ->
        fields =
          attrs
          |> Enum.flat_map(fn {key, val} ->
            try do
              [{String.to_existing_atom(key), val}]
            rescue
              ArgumentError -> []
            end
          end)
          |> Enum.filter(fn {key, _} -> Map.has_key?(module.__struct__(), key) end)

        struct(module, fields)

      {:error, _} ->
        nil
    end
  rescue
    _ -> nil
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
      observation_state: Map.get(ctx, :ObservationState, 0)
    }
  end

  defp schedule_stream_reconnect(%{reconnect_timer: timer} = state) when not is_nil(timer),
    do: state

  defp schedule_stream_reconnect(state) do
    timer = Process.send_after(self(), :reopen, @stream_reconnect_delay)
    %{state | reconnect_timer: timer}
  end

  # Tears down the current observation stream and receiver task, returning a
  # clean state ready to (re)establish.
  defp teardown(state) do
    cleanup_stream(state)
    shutdown_task(state.receiver_task)
    cancel_timer(state.reconnect_timer)
    %{state | stream: nil, receiver_task: nil, reconnect_timer: nil}
  end

  defp cleanup_stream(%{stream: nil}), do: :ok

  defp cleanup_stream(%{stream: stream}) do
    try do
      GRPC.Stub.end_stream(stream)
    rescue
      _ -> :ok
    end
  end

  defp shutdown_task(nil), do: :ok
  defp shutdown_task(%Task{} = task), do: Task.shutdown(task, :brutal_kill)
  defp shutdown_task(_), do: :ok

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  # ObservationState enum: Success = 1, Failed = 2
  defp encode_observation_state(:success), do: 1
  defp encode_observation_state(:failed), do: 2

  defp format_stack_trace(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_stack_trace(reason), do: inspect(reason)
end
