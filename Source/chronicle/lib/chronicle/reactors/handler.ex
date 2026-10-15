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

  alias Chronicle.Connections.{Connection, Lifecycle, Status}
  alias Chronicle.Reactors.Dispatch

  alias Cratis.Chronicle.Contracts.Observation.Reactors.{
    Reactors,
    ReactorMessage,
    ReactorDefinition,
    RegisterReactor,
    EventTypeWithKeyExpression,
    ObserverFilters
  }

  alias Cratis.Chronicle.Contracts.Observation.Reactors.EventType, as: ProtoEventType

  alias Cratis.Chronicle.Contracts.Observation.Reactors.OneOf_RegisterReactor_ReactorResult,
    as: OneOf

  alias Chronicle.Observers.GenerationDeliveryValidation

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

    generation_delivery =
      module.__chronicle_reactor__(:generation_delivery) ||
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
      client: client,
      connection: Keyword.fetch!(opts, :connection),
      lifecycle: Keyword.get(opts, :lifecycle),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.fetch!(opts, :namespace),
      event_type_map: event_type_map,
      generation_delivery: generation_delivery,
      establish_fun: Keyword.get(opts, :establish_fun, &default_establish/2),
      append_fun:
        Keyword.get(opts, :append_fun, fn operation ->
          Dispatch.default_append(operation, client)
        end),
      connection_id: nil,
      stream: nil,
      receiver_task: nil,
      reconnect_timer: nil
    }

    if state.lifecycle, do: Lifecycle.subscribe(state.lifecycle)

    {:ok, state}
  end

  @impl true
  def format_status(%{state: state} = status) do
    Status.redact(status,
      stream: if(state.stream, do: :open, else: nil),
      establish_fun: :redacted,
      append_fun: :redacted
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
                  IsReplayable: not once_only_class?(state.module),
                  IsNotReplayable: once_only_class?(state.module),
                  StartAtTail: state.module.__chronicle_reactor__(:start_at_tail),
                  Tags: [],
                  Filters: struct(ObserverFilters),
                  GenerationDelivery: encode_generation_delivery(state.generation_delivery)
                )
            )
        )
    )
  end

  defp dispatch_event_batch(events_to_observe, state) do
    result = Dispatch.build_result(state, events_to_observe)
    GRPC.Stub.send_request(state.stream, result)
    {:noreply, state}
  end

  # Thin delegates kept on Handler (rather than inlined) so existing specs calling
  # Handler.handle_result/3 and Handler.side_effect_operation/2 directly keep working
  # unchanged after the dispatch logic moved to Chronicle.Reactors.Dispatch.
  @doc false
  defdelegate handle_result(result, state, event_source_id), to: Dispatch

  @doc false
  defdelegate side_effect_operation(side_effect, event_source_id), to: Dispatch

  # EventGenerationDelivery enum: Compatibility = 0, Pinned = 1.
  defp encode_generation_delivery(:pinned), do: :Pinned
  defp encode_generation_delivery(_compatibility), do: :Compatibility

  @doc false
  defdelegate once_only_class?(module), to: Dispatch

  @doc false
  defdelegate replay_action(module, event_module, context), to: Dispatch

  @doc false
  defdelegate build_context(ctx, opts \\ []), to: Dispatch

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

  # ReplayState enum: None = 0, BeginReplay = 1, EndReplay = 2,
  # BeginReplayPartition = 3, EndReplayPartition = 4.
  defp replay_state(events_to_observe) do
    case Map.get(events_to_observe, :ReplayState, :REPLAY_STATE_None) do
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
