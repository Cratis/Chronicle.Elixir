# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.Handler do
  @moduledoc false

  # GenServer that maintains a bidirectional gRPC stream with Chronicle for a
  # single reducer module. Chronicle sends ReduceOperationMessage batches
  # containing the current read model state and the events to apply. The
  # handler calls the reducer's reduce/3 callback for each event and returns
  # the resulting read model JSON.
  #
  # When the stream ends, the handler opens it again after a jittered wait that
  # grows while streams keep ending without having worked (see
  # Chronicle.Observers.ReconnectBackoff). When the kernel no longer knows the
  # client's connection id, the handler asks the session for a full reconnect
  # with a new connection id instead, and re-registers on the next :registered.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.{Connection, Lifecycle, Session, Status}
  alias Chronicle.Reducers.Dispatch

  alias Chronicle.Observers.{
    BatchFunctions,
    BatchRunner,
    PageDeliveryOptions,
    ReconnectBackoff,
    StreamErrors
  }

  alias Cratis.Chronicle.Contracts.Observation.Reducers.{
    PageDelivery,
    Reducers,
    ReducerMessage,
    ReducerDefinition,
    RegisterReducer,
    EventTypeWithKeyExpression,
    ObserverFilters
  }

  alias Cratis.Chronicle.Contracts.Observation.Reducers.EventType, as: ProtoEventType

  alias Cratis.Chronicle.Contracts.Observation.Reducers.OneOf_RegisterReducer_ReducerResult,
    as: OneOf

  alias Chronicle.Observers.GenerationDeliveryValidation

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    client = Keyword.get(opts, :client, Chronicle.Client)
    # Raises when the reducer mixes a batch function with reduce/3, or has two batch functions,
    # so a mixed-up reducer never registers.
    functions = BatchFunctions.validate!(:reducer, module)
    event_type_modules = module.__chronicle_reducer__(:handles)

    generation_delivery =
      module.__chronicle_reducer__(:generation_delivery) ||
        Keyword.get(opts, :event_generation_delivery, :compatibility)

    if generation_delivery == :pinned do
      GenerationDeliveryValidation.validate!(event_type_modules)
    end

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
      batch_functions: functions.batch,
      max_concurrency:
        PageDeliveryOptions.max_concurrency(module.__chronicle_reducer__(:batch_size)),
      generation_delivery: generation_delivery,
      model_module: module.__chronicle_reducer__(:model),
      default_sink_type_id: Keyword.get(opts, :default_sink_type_id, "MongoDB"),
      establish_fun: Keyword.get(opts, :establish_fun, &default_establish/2),
      send_fun: Keyword.get(opts, :send_fun, &GRPC.Stub.send_request/2),
      session_lost_fun:
        Keyword.get(opts, :session_lost_fun, fn connection_id ->
          Session.session_lost(Session.name_for(client), connection_id)
        end),
      send_after_fun: Keyword.get(opts, :send_after_fun, &Process.send_after(self(), &1, &2)),
      backoff: ReconnectBackoff.new(Keyword.get(opts, :observation_reconnect) || []),
      connection_id: nil,
      stream: nil,
      receiver_task: nil,
      reconnect_timer: nil
    }

    state = Map.merge(state, BatchRunner.init(opts))

    if state.lifecycle, do: Lifecycle.subscribe(state.lifecycle)

    {:ok, state}
  end

  @impl true
  def format_status(%{state: state} = status) do
    Status.redact(status,
      stream: if(state.stream, do: :open, else: nil),
      establish_fun: :redacted,
      send_fun: :redacted,
      session_lost_fun: :redacted,
      send_after_fun: :redacted
    )
  end

  @impl true
  def handle_call(_request, _from, _state) do
    raise FunctionClauseError, module: __MODULE__, function: :handle_call, arity: 3
  end

  @impl true
  def handle_cast(_message, _state) do
    raise FunctionClauseError, module: __MODULE__, function: :handle_cast, arity: 2
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

  def handle_info({:reduce_operation, reduce_op}, state),
    do: handle_info({:reduce_operation, reduce_op, now_ms()}, state)

  # Operations for different read models run concurrently, each read model's in
  # order; replay notifications keep their place relative to the operations around them.
  # A page that spans several read models runs on its own.
  def handle_info({:reduce_operation, reduce_op, received_at}, state) do
    partition = Map.get(reduce_op, :Partition, "")
    state = %{state | backoff: ReconnectBackoff.stream_delivered(state.backoff)}

    state =
      case replay_state(reduce_op) do
        :none ->
          BatchRunner.delivery(state, reduce_op, received_at, hooks())

        signal when signal in [:begin_replay, :end_replay] ->
          BatchRunner.barrier(state, {:replay, signal, partition}, hooks())

        signal ->
          BatchRunner.inline(state, partition, {:replay, signal, partition}, hooks())
      end

    {:noreply, state}
  end

  def handle_info({:batch_finished, tag, outcome}, state) do
    case BatchRunner.finished(state, tag, outcome, hooks()) do
      {:ok, state} -> {:noreply, state}
      {:send_failed, state} -> {:noreply, schedule_stream_reconnect(teardown(state))}
    end
  end

  def handle_info({:stream_down, pid, reason}, %{receiver_task: %Task{pid: pid}} = state) do
    {:noreply, stream_ended(state, reason, "stream disconnected")}
  end

  # A stream that has already been replaced - its report was in flight while the
  # handler opened a new one. Acting on it would tear down the current stream.
  def handle_info({:stream_down, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{receiver_task: %Task{pid: pid}} = state) do
    {:noreply, stream_ended(state, reason, "receiver task exited")}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case BatchRunner.down(state, monitor, reason, hooks()) do
      {:send_failed, state} -> {:noreply, schedule_stream_reconnect(teardown(state))}
      {_, state} -> {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # The kernel no longer knows this client's connection id. Retrying the same
  # stream with it can never work, so ask the session for a full reconnect with a
  # new connection id; the next :registered re-registers this reducer. Without a
  # lifecycle there is no :registered to wait for, so reopen the stream instead.
  defp stream_ended(state, reason, what) do
    case StreamErrors.classify(reason) do
      :session_lost when not is_nil(state.lifecycle) ->
        Logger.warning(
          "Reducer #{state.module} lost its kernel session, reconnecting the client: #{inspect(reason)}"
        )

        connection_id = state.connection_id
        state = teardown(state)
        state.session_lost_fun.(connection_id)
        state

      _ ->
        Logger.warning("Reducer #{state.module} #{what}: #{inspect(reason)}")
        schedule_stream_reconnect(teardown(state))
    end
  end

  # Opens the observation stream for the current connection id, returning the
  # updated state. On failure it schedules a stream-level reconnect.
  defp establish(state) do
    state = %{state | backoff: ReconnectBackoff.stream_opened(state.backoff)}

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
  catch
    :exit, reason -> {:error, reason}
  end

  defp registered?(%{lifecycle: nil}), do: true
  defp registered?(%{lifecycle: lifecycle}), do: Lifecycle.phase(lifecycle) == :registered

  defp receive_loop(handler, stream) do
    case GRPC.Stub.recv(stream) do
      {:ok, reply_stream} ->
        Enum.each(reply_stream, fn
          {:ok, reduce_op} ->
            # Stamped on arrival: the kernel's delivery deadline counts from here.
            send(handler, {:reduce_operation, reduce_op, System.monotonic_time(:millisecond)})

          {:error, reason} ->
            send(handler, {:stream_down, self(), reason})
        end)

      {:error, reason} ->
        send(handler, {:stream_down, self(), reason})
    end
  end

  # The reducer's sink is part of its read model's registration (see
  # Chronicle.Registration.Coordinator); the reducer definition itself carries none.
  # Public so the registration message can be asserted directly in a spec.
  @doc false
  def build_registration(state, conn_id) do
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
              # Opts in to pages; a kernel that predates them ignores the field.
              PageDelivery:
                PageDeliveryOptions.to_wire(
                  PageDelivery,
                  state.module.__chronicle_reducer__(:batch_size)
                ),
              Reducer:
                struct(ReducerDefinition,
                  ReducerId: reducer_id,
                  EventSequenceId: "event-log",
                  EventTypes: event_types,
                  ReadModel: model_id,
                  IsActive: state.module.__chronicle_reducer__(:active),
                  Tags: [],
                  Filters: struct(ObserverFilters),
                  GenerationDelivery: encode_generation_delivery(state.generation_delivery)
                )
            )
        )
    )
  end

  defp hooks do
    %{
      kind: :reducer,
      build_result: &Dispatch.build_result/2,
      expired_result: &Dispatch.expired_result/2,
      notify: fn state, {:replay, signal, partition} ->
        notify_replay(state.module, signal, partition)
      end
    }
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  @doc false
  defdelegate build_context(ctx, opts \\ []), to: Dispatch

  # EventGenerationDelivery enum: Compatibility = 0, Pinned = 1.
  defp encode_generation_delivery(:pinned), do: :Pinned
  defp encode_generation_delivery(_compatibility), do: :Compatibility

  defp schedule_stream_reconnect(%{reconnect_timer: timer} = state) when not is_nil(timer),
    do: state

  defp schedule_stream_reconnect(state) do
    {delay, backoff} = ReconnectBackoff.next_delay(state.backoff)
    timer = state.send_after_fun.(:reopen, delay)
    %{state | reconnect_timer: timer, backoff: backoff}
  end

  # Tears down the current observation stream and receiver task, returning a
  # clean state ready to (re)establish.
  defp teardown(state) do
    state = BatchRunner.reset(state)
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

  # ReplayState enum: None = 0, BeginReplay = 1, EndReplay = 2,
  # BeginReplayPartition = 3, EndReplayPartition = 4.
  defp replay_state(reduce_op) do
    case Map.get(reduce_op, :ReplayState, :REPLAY_STATE_None) do
      none when none in [:REPLAY_STATE_None, 0] ->
        :none

      begin_replay when begin_replay in [:BeginReplay, 1] ->
        :begin_replay

      end_replay when end_replay in [:EndReplay, 2] ->
        :end_replay

      begin_partition when begin_partition in [:BeginReplayPartition, 3] ->
        :begin_replay_partition

      end_partition when end_partition in [:EndReplayPartition, 4] ->
        :end_replay_partition

      _ ->
        :none
    end
  end

  # Invokes the reducer module's optional replay-lifecycle callback (see
  # Chronicle.Reducers.Reducer) for a replay-state transition. These are
  # notifications, not events dispatched through reduce/3 — no ReducerResult
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
    e -> Logger.warning("Reducer #{module} replay callback #{callback} raised: #{inspect(e)}")
  end
end
