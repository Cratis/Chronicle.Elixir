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

  alias Chronicle.Connections.{Connection, Lifecycle}
  alias Chronicle.EventSequences.{EventForEventSourceId, EventLog}

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

  alias Cratis.Chronicle.Contracts.Observation.Reactors.OneOf_RegisterReactor_ReactorResult,
    as: OneOf

  # Stream-level reconnect delay (matches the C# client's per-stream retry).
  @stream_reconnect_delay 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    client = Keyword.get(opts, :client, Chronicle.Client)
    event_type_modules = module.__chronicle_reactor__(:handles)

    event_type_map =
      Map.new(event_type_modules, fn et_module ->
        {et_module.__chronicle_event_type__(:id), et_module}
      end)

    state = %{
      module: module,
      client: client,
      connection: Keyword.fetch!(opts, :connection),
      lifecycle: Keyword.get(opts, :lifecycle),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.fetch!(opts, :namespace),
      event_type_map: event_type_map,
      establish_fun: Keyword.get(opts, :establish_fun, &default_establish/2),
      append_fun:
        Keyword.get(opts, :append_fun, fn operation -> default_append(operation, client) end),
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
    state = teardown(%{state | connection_id: connection_id})
    {:noreply, establish(state)}
  end

  def handle_info({:chronicle_lifecycle, :connected, _connection_id}, state) do
    # Connected but not yet registered — wait for :registered before observing.
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
      {:noreply, state}
    end
  end

  def handle_info({:event_batch, events_to_observe}, state) do
    case replay_state(events_to_observe) do
      :none ->
        dispatch_event_batch(events_to_observe, state)

      replay_signal ->
        notify_replay(state.module, replay_signal, Map.get(events_to_observe, :Partition, ""))
        {:noreply, state}
    end
  end

  def handle_info({:stream_down, reason}, state) do
    Logger.warning("Reactor #{state.module} stream disconnected: #{inspect(reason)}")
    {:noreply, schedule_stream_reconnect(teardown(state))}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{receiver_task: %Task{pid: pid}} = state) do
    Logger.warning("Reactor #{state.module} receiver task exited: #{inspect(reason)}")
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
        Logger.warning("Reactor #{state.module} failed to register: #{inspect(reason)}")
        schedule_stream_reconnect(state)
    end
  end

  defp default_establish(state, connection_id) do
    case Connection.channel(state.connection) do
      {:ok, channel} ->
        stream = Reactors.Stub.observe(channel)
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
          {:ok, events_to_observe} ->
            send(handler, {:event_batch, events_to_observe})

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

    reactor_id = state.module.__chronicle_reactor__(:id)

    struct(ReactorMessage,
      Content:
        struct(OneOf,
          Value0:
            struct(RegisterReactor,
              ConnectionId: conn_id,
              EventStore: state.event_store,
              Namespace: state.namespace,
              Reactor:
                struct(ReactorDefinition,
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

  defp dispatch_event_batch(events_to_observe, state) do
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

    result =
      struct(ReactorMessage,
        Content:
          struct(OneOf,
            Value1:
              struct(ReactorResult,
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
              event
              |> state.module.handle(ctx)
              |> handle_result(state, ctx.event_source_id)
            rescue
              e -> {:error, e}
            end

          {:error, reason} ->
            Logger.warning("Failed to decode event #{event_type_id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  # Normalizes handle/2's return value to :ok | {:error, reason}, appending
  # any returned side-effect event(s) via the triggering event source id (or
  # each EventForEventSourceId's own explicit target). Public (but @doc false)
  # so it can be exercised directly in tests against a minimal state map
  # carrying just :append_fun, without a live connection.
  @doc false
  def handle_result(:ok, _state, _event_source_id), do: :ok
  def handle_result({:error, _reason} = error, _state, _event_source_id), do: error

  def handle_result({:ok, side_effect}, state, event_source_id) do
    side_effect
    |> side_effect_operation(event_source_id)
    |> perform_append(state)
  end

  def handle_result(_other, _state, _event_source_id), do: :ok

  # Translates a handle/2 side-effect return value into an append instruction,
  # a pure decision kept separate from performing the actual append (see
  # perform_append/2) so it can be exercised without a live connection.
  @doc false
  def side_effect_operation(nil, _event_source_id), do: :noop

  def side_effect_operation(%EventForEventSourceId{} = wrapped, _event_source_id) do
    {:append, wrapped.event_source_id, wrapped.event,
     [
       event_source_type: wrapped.event_source_type,
       event_stream_type: wrapped.event_stream_type,
       event_stream_id: wrapped.event_stream_id,
       tags: wrapped.tags,
       subject: wrapped.subject,
       occurred: wrapped.occurred,
       concurrency_scope: wrapped.concurrency_scope,
       causation: wrapped.causation,
       identity: wrapped.identity
     ]
     |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)}
  end

  def side_effect_operation(events, event_source_id) when is_list(events) do
    cond do
      events == [] ->
        :noop

      Enum.all?(events, &match?(%EventForEventSourceId{}, &1)) ->
        {:append_many_for_event_sources, events}

      Enum.any?(events, &match?(%EventForEventSourceId{}, &1)) ->
        normalized =
          Enum.map(events, fn
            %EventForEventSourceId{} = wrapped -> wrapped
            event -> %EventForEventSourceId{event_source_id: event_source_id, event: event}
          end)

        {:append_many_for_event_sources, normalized}

      true ->
        {:append_many, event_source_id, events}
    end
  end

  def side_effect_operation(%_{} = event, event_source_id) do
    {:append, event_source_id, event, []}
  end

  def side_effect_operation(_other, _event_source_id), do: :noop

  defp perform_append(:noop, _state), do: :ok
  defp perform_append(operation, state), do: state.append_fun.(operation)

  defp default_append({:append, event_source_id, event, opts}, client) do
    EventLog.append(event_source_id, event, Keyword.put(opts, :client, client))
  end

  defp default_append({:append_many, event_source_id, events}, client) do
    EventLog.append_many(event_source_id, events, client: client)
  end

  defp default_append({:append_many_for_event_sources, events}, client) do
    EventLog.append_many_for_event_sources(events, client: client)
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
    catch
      _, _ -> :ok
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

  # ReplayState enum: None = 0, BeginReplay = 1, EndReplay = 2,
  # BeginReplayPartition = 3, EndReplayPartition = 4.
  defp replay_state(events_to_observe) do
    case Map.get(events_to_observe, :ReplayState, :REPLAY_STATE_None) do
      none when none in [:REPLAY_STATE_None, 0] -> :none
      begin_replay when begin_replay in [:BeginReplay, 1] -> :begin_replay
      end_replay when end_replay in [:EndReplay, 2] -> :end_replay
      begin_partition when begin_partition in [:BeginReplayPartition, 3] -> :begin_replay_partition
      end_partition when end_partition in [:EndReplayPartition, 4] -> :end_replay_partition
      _ -> :none
    end
  end

  # Invokes the reactor module's optional replay-lifecycle callback (see
  # Chronicle.Reactors.Reactor) for a replay-state transition. These are
  # notifications, not events dispatched through handle/2 — no ReactorResult
  # is sent back to Chronicle for them (mirroring the C# client), and a
  # raised exception is logged and swallowed rather than failing the stream.
  defp notify_replay(module, :begin_replay, _partition),
    do: safely_notify(module, :on_replay_begin, [])

  defp notify_replay(module, :end_replay, _partition),
    do: safely_notify(module, :on_replay_end, [])

  defp notify_replay(module, :begin_replay_partition, partition),
    do: safely_notify(module, :on_partition_replay_begin, [partition])

  defp notify_replay(module, :end_replay_partition, partition),
    do: safely_notify(module, :on_partition_replay_end, [partition])

  defp safely_notify(module, callback, args) do
    if function_exported?(module, callback, length(args)) do
      apply(module, callback, args)
    end
  rescue
    e -> Logger.warning("Reactor #{module} replay callback #{callback} raised: #{inspect(e)}")
  end
end
