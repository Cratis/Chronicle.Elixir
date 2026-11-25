# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Observers.Multiplexed.Channel do
  @moduledoc false

  # Carries every reactor and reducer of a client over one bidirectional call to the kernel
  # (`MultiplexedObservation.Observe`) instead of one call each, mirroring the .NET client's
  # `MultiplexedObservationChannel`.
  #
  #   * The call is opened by the first observer that opens a stream and ended when the last one
  #     closes. After it failed, the next stream opens a new one.
  #   * It is used only when the kernel advertises the `multiplexed-observation` capability and
  #     the `:multiplex_observation` client option is on (the default). Otherwise `open/4`
  #     answers `:unsupported` and the observer opens its own call as before.
  #   * Messages queued within `flush_interval` go out in one write, at most `max_batch` at a time,
  #     so all observers register together at start-up and after a reconnect.
  #   * Each stream has its own queue, read by its own handler, so a slow observer never holds
  #     back another. The channel itself never waits on a handler.
  #   * The kernel numbers the messages of each stream. A gap fails the whole call, and so does
  #     any failure of the shared call: every open stream then ends with the error and its handler
  #     reopens, on a new call, the way it reopens after any lost connection.
  #   * A stream the kernel ends with a non-zero status ends with the `GRPC.RPCError` a failed
  #     per-observer call would have given, so the handlers' error classification is unchanged.

  use GenServer

  require Logger

  alias Cratis.Chronicle.Connections.{AppendCompatibility, ResponseProcesses}
  alias Cratis.Chronicle.Observers.Multiplexed.ObserverStream
  alias Cratis.Chronicle.Contracts.Observation.{Reactors, Reducers}

  alias Cratis.Chronicle.Contracts.Observation.Multiplexed, as: Wire

  @capability "multiplexed-observation"
  @flush_interval 10
  @max_batch 500
  @internal_status 13

  @doc "The registered name of a client's multiplexed observation channel."
  @spec name_for(atom()) :: atom()
  def name_for(client), do: :"#{client}.MultiplexedObservation"

  @doc """
  Options: `:name`, `:enabled` (default `true`) and test seams `:capabilities_fun`, `:open_fun`,
  `:send_fun`, `:recv_fun`, `:end_fun`, `:flush_interval` and `:max_batch`.
  """
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Opens a stream for an observer on the shared call and sends its registration as the first
  message of the stream.

  Returns `:unsupported` when the observer must use its own call.
  """
  @spec open(GenServer.server(), GRPC.Channel.t(), :reactor | :reducer, struct()) ::
          {:ok, ObserverStream.t()} | :unsupported | {:error, term()}
  def open(server, grpc_channel, kind, registration) do
    GenServer.call(server, {:open, grpc_channel, kind, registration}, 30_000)
  end

  @doc false
  @spec send_message(ObserverStream.t(), struct()) :: :ok | {:error, term()}
  def send_message(%ObserverStream{server: server, id: id}, message),
    do: GenServer.call(server, {:send, id, message})

  @doc false
  @spec next(ObserverStream.t()) :: {:message, term()} | :done | {:error, term()}
  def next(%ObserverStream{server: server, id: id}) do
    GenServer.call(server, {:next, id}, :infinity)
  catch
    :exit, reason -> {:error, {:multiplexed_observation_unavailable, reason}}
  end

  @doc "Ends the stream of an observer: tells the kernel to stop observing for it."
  @spec close(ObserverStream.t()) :: :ok
  def close(%ObserverStream{server: server, id: id}) do
    GenServer.call(server, {:close, id})
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       enabled?: Keyword.get(opts, :enabled, true),
       capabilities_fun:
         Keyword.get(opts, :capabilities_fun, &AppendCompatibility.capabilities/1),
       open_fun: Keyword.get(opts, :open_fun, &default_open/1),
       send_fun: Keyword.get(opts, :send_fun, &GRPC.Stub.send_request/2),
       recv_fun: Keyword.get(opts, :recv_fun, &GRPC.Stub.recv/1),
       end_fun: Keyword.get(opts, :end_fun, &default_end/1),
       flush_interval: Keyword.get(opts, :flush_interval, @flush_interval),
       max_batch: Keyword.get(opts, :max_batch, @max_batch),
       supported: nil,
       call: nil,
       streams: %{},
       outbox: [],
       flush_timer: nil,
       next_id: 1
     }}
  end

  @impl true
  def handle_call({:open, grpc_channel, kind, registration}, {owner, _}, state) do
    with {:ok, state} <- check_supported(state, grpc_channel),
         {:ok, state} <- ensure_call(state, grpc_channel) do
      {id, state} = open_stream(state, kind, owner, registration)
      {:reply, {:ok, %ObserverStream{server: self(), id: id, kind: kind}}, state}
    else
      {:unsupported, state} -> {:reply, :unsupported, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send, id, message}, _from, state) do
    case state.streams do
      %{^id => %{terminal: nil, kind: kind}} ->
        {:reply, :ok, enqueue(state, stream_message(id, kind, message))}

      _ ->
        {:reply, {:error, :stream_closed}, state}
    end
  end

  def handle_call({:next, id}, from, state) do
    case state.streams do
      %{^id => stream} -> {:noreply, next_for(state, id, stream, from)}
      _ -> {:reply, :done, state}
    end
  end

  def handle_call({:close, id}, _from, state), do: {:reply, :ok, release(state, id)}

  @impl true
  def handle_info(:flush, state), do: {:noreply, flush(%{state | flush_timer: nil})}

  def handle_info({:reply, ref, message}, %{call: %{ref: ref}} = state),
    do: {:noreply, received(state, message)}

  def handle_info({:call_ended, ref, outcome}, %{call: %{ref: ref}} = state),
    do: {:noreply, fail_call(state, outcome)}

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case state.call do
      %{reader_monitor: ^monitor} when reason != :normal ->
        {:noreply, fail_call(state, {:error, {:reader_down, reason}})}

      _ ->
        {:noreply, owner_down(state, monitor)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.call, do: end_call(state, state.call)
    :ok
  end

  # --- capability and call lifecycle ---

  defp check_supported(%{enabled?: false} = state, _channel), do: {:unsupported, state}

  defp check_supported(%{supported: {channel, supported?}} = state, channel),
    do: if(supported?, do: {:ok, state}, else: {:unsupported, state})

  defp check_supported(state, channel) do
    case state.capabilities_fun.(channel) do
      {:ok, capabilities} ->
        supported? = @capability in capabilities
        state = %{state | supported: {channel, supported?}}
        if supported?, do: {:ok, state}, else: {:unsupported, state}

      {:error, reason} ->
        # Not remembered: a kernel that could not be asked now may be asked again.
        Logger.debug(
          "Multiplexed observation not used, capability check failed: #{inspect(reason)}"
        )

        {:unsupported, state}
    end
  end

  defp ensure_call(%{call: %{}} = state, _channel), do: {:ok, state}

  defp ensure_call(state, channel) do
    case safely(fn -> state.open_fun.(channel) end) do
      {:ok, call, response_processes} ->
        ref = make_ref()
        server = self()
        recv_fun = state.recv_fun

        {reader, reader_monitor} =
          spawn_monitor(fn -> read_replies(server, ref, call, recv_fun) end)

        call = %{
          ref: ref,
          stream: call,
          reader: reader,
          reader_monitor: reader_monitor,
          response_processes: response_processes
        }

        {:ok, %{state | call: call}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp default_open(grpc_channel) do
    snapshot = ResponseProcesses.snapshot()

    case Wire.MultiplexedObservation.Stub.observe(grpc_channel) do
      %GRPC.Client.Stream{payload: %{response: {:error, reason}}} ->
        snapshot |> ResponseProcesses.started_since() |> ResponseProcesses.stop()
        {:error, reason}

      stream ->
        {:ok, stream, ResponseProcesses.started_since(snapshot)}
    end
  end

  defp default_end(stream) do
    GRPC.Stub.end_stream(stream)
    :ok
  end

  defp read_replies(server, ref, call, recv_fun) do
    outcome =
      case recv_fun.(call) do
        {:ok, replies} ->
          Enum.reduce_while(replies, :done, fn
            {:ok, message}, outcome ->
              send(server, {:reply, ref, message})
              {:cont, outcome}

            {:error, reason}, _outcome ->
              {:halt, {:error, reason}}
          end)

        {:error, reason} ->
          {:error, reason}
      end

    send(server, {:call_ended, ref, outcome})
  end

  # Ends the call, leaving no process behind.
  defp end_call(state, call) do
    Process.demonitor(call.reader_monitor, [:flush])
    Process.exit(call.reader, :kill)
    ended(state, call)
    ResponseProcesses.stop(call.response_processes)
    :ok
  end

  defp ended(state, call) do
    state.end_fun.(call.stream)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  # --- streams ---

  defp open_stream(state, kind, owner, registration) do
    id = state.next_id

    stream = %{
      kind: kind,
      call_ref: state.call.ref,
      queue: :queue.new(),
      expected: 1,
      terminal: nil,
      waiter: nil,
      owner_monitor: Process.monitor(owner)
    }

    first = %{stream_message(id, kind, registration) | Kind: kind_atom(kind)}

    state = %{state | next_id: id + 1, streams: Map.put(state.streams, id, stream)}
    {id, enqueue(state, first)}
  end

  defp kind_atom(:reactor), do: :Reactor
  defp kind_atom(:reducer), do: :Reducer

  defp stream_message(id, :reactor, message),
    do: %Wire.MultiplexedStreamMessage{
      StreamId: id,
      Reactor: recode(message, Wire.ReactorMessage)
    }

  defp stream_message(id, :reducer, message),
    do: %Wire.MultiplexedStreamMessage{
      StreamId: id,
      Reducer: recode(message, Wire.ReducerMessage)
    }

  # The per-observer and multiplexed contracts are separate generated modules for the same wire
  # messages, so a message built for one is read into the other through its encoding.
  defp recode(%module{} = message, module), do: message
  defp recode(%module{} = message, target), do: target.decode(module.encode(message))

  defp delivered(:reactor, message), do: recode(message, Reactors.EventsToObserve)
  defp delivered(:reducer, message), do: recode(message, Reducers.ReduceOperationMessage)

  defp next_for(state, id, stream, from) do
    case :queue.out(stream.queue) do
      {{:value, item}, queue} ->
        GenServer.reply(from, {:message, item})
        put_stream(state, id, %{stream | queue: queue})

      {:empty, _} ->
        case stream.terminal do
          nil -> put_stream(state, id, %{stream | waiter: from})
          terminal -> reply_and(state, from, terminal)
        end
    end
  end

  defp reply_and(state, from, reply) do
    GenServer.reply(from, reply)
    state
  end

  defp put_stream(state, id, stream), do: %{state | streams: Map.put(state.streams, id, stream)}

  defp received(state, %Wire.MultiplexedServerMessage{StreamId: id, Sequence: sequence} = message) do
    case state.streams do
      %{^id => %{terminal: nil, expected: ^sequence} = stream} ->
        stream = %{stream | expected: sequence + 1}
        demultiplex(put_stream(state, id, stream), id, stream, message)

      %{^id => %{terminal: nil, expected: expected}} ->
        gap = "multiplexed stream #{id} expected message #{expected} but got #{sequence}"
        fail_call(state, {:error, %GRPC.RPCError{status: @internal_status, message: gap}})

      _ ->
        # A stream that is already ended or closed: late messages are dropped.
        state
    end
  end

  defp demultiplex(state, id, stream, message) do
    cond do
      message."End" != nil ->
        end_stream(state, id, stream, message."End")

      message."Reactor" != nil ->
        deliver(state, id, stream, delivered(:reactor, message."Reactor"))

      message."Reducer" != nil ->
        deliver(state, id, stream, delivered(:reducer, message."Reducer"))

      true ->
        state
    end
  end

  defp end_stream(state, id, stream, %{StatusCode: 0}),
    do: terminate_stream(state, id, stream, :done)

  defp end_stream(state, id, stream, %{StatusCode: status, Detail: detail}) do
    error = %GRPC.RPCError{status: status, message: detail}
    terminate_stream(state, id, stream, {:error, error})
  end

  defp deliver(state, id, %{waiter: nil} = stream, item),
    do: put_stream(state, id, %{stream | queue: :queue.in(item, stream.queue)})

  defp deliver(state, id, %{waiter: waiter} = stream, item) do
    GenServer.reply(waiter, {:message, item})
    put_stream(state, id, %{stream | waiter: nil})
  end

  defp terminate_stream(state, id, %{waiter: nil} = stream, terminal),
    do: put_stream(state, id, %{stream | terminal: terminal})

  defp terminate_stream(state, id, %{waiter: waiter} = stream, terminal) do
    GenServer.reply(waiter, terminal)
    put_stream(state, id, %{stream | terminal: terminal, waiter: nil})
  end

  # The shared call failed or ended: every stream still open on it ends the same way.
  defp fail_call(%{call: nil} = state, _outcome), do: state

  defp fail_call(state, outcome) do
    call = state.call

    case outcome do
      {:error, reason} ->
        Logger.warning("The multiplexed observation call failed: #{inspect(reason)}")

      :done ->
        :ok
    end

    end_call(state, call)
    state = cancel_flush(%{state | call: nil, outbox: []})

    Enum.reduce(state.streams, state, fn
      {id, %{call_ref: ref, terminal: nil} = stream}, state when ref == call.ref ->
        terminate_stream(state, id, stream, outcome)

      _, state ->
        state
    end)
  end

  # An observer is done with its stream: tell the kernel, and end the call with the last one.
  defp release(state, id) do
    case Map.pop(state.streams, id) do
      {nil, _streams} ->
        state

      {stream, streams} ->
        Process.demonitor(stream.owner_monitor, [:flush])
        if stream.waiter, do: GenServer.reply(stream.waiter, :done)
        state = %{state | streams: streams}

        if stream.terminal == nil and current?(state, stream) do
          close_on_call(state, id, stream)
        else
          state
        end
    end
  end

  defp current?(%{call: %{ref: ref}}, %{call_ref: ref}), do: true
  defp current?(_state, _stream), do: false

  defp close_on_call(state, id, stream) do
    state = enqueue(state, %Wire.MultiplexedStreamMessage{StreamId: id, Close: true})

    if Enum.any?(state.streams, fn {_id, other} -> other.call_ref == stream.call_ref end) do
      state
    else
      state = flush(state)

      case state.call do
        nil ->
          state

        call ->
          end_call(state, call)
          %{state | call: nil}
      end
    end
  end

  defp owner_down(state, monitor) do
    case Enum.find(state.streams, fn {_id, stream} -> stream.owner_monitor == monitor end) do
      {id, _stream} -> release(state, id)
      nil -> state
    end
  end

  # --- writes ---

  defp enqueue(state, message) do
    state = %{state | outbox: [message | state.outbox]}

    if state.flush_timer == nil do
      %{state | flush_timer: Process.send_after(self(), :flush, state.flush_interval)}
    else
      state
    end
  end

  defp cancel_flush(%{flush_timer: nil} = state), do: state

  defp cancel_flush(state) do
    Process.cancel_timer(state.flush_timer)
    %{state | flush_timer: nil}
  end

  defp flush(%{outbox: []} = state), do: cancel_flush(state)
  defp flush(%{call: nil} = state), do: cancel_flush(%{state | outbox: []})

  defp flush(state) do
    batches = state.outbox |> Enum.reverse() |> Enum.chunk_every(state.max_batch)
    state = cancel_flush(%{state | outbox: []})
    call = state.call

    Enum.reduce_while(batches, state, fn batch, state ->
      write = fn ->
        {:ok, state.send_fun.(call.stream, %Wire.MultiplexedClientMessage{Messages: batch})}
      end

      case safely(write) do
        {:ok, _} -> {:cont, state}
        {:error, reason} -> {:halt, fail_call(state, {:error, reason})}
      end
    end)
  end

  defp safely(fun) do
    case fun.() do
      {:ok, _} = ok -> ok
      {:ok, _, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:ok, other}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
