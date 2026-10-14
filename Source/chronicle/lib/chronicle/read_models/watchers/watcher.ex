# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Watchers.Watcher do
  @moduledoc false

  # Owns one shared kernel `Watch` stream for a single `{client, namespace, model, event_sequence_id}`
  # key and fans its changesets out to every subscriber of `Chronicle.ReadModels.subscribe/2`.
  #
  # The stream itself is read by a separate, monitored worker process (`run_stream/3`) rather than
  # inline, because consuming a gRPC server stream blocks on `Enum.each/2` — running it in the
  # `GenServer` itself would make it unable to receive `subscribe`/`unsubscribe` calls or react to a
  # subscriber's exit while the stream is open.
  #
  # On a stream failure (the worker exits for any reason while subscribers remain) every subscriber
  # receives `{:chronicle_read_model_watch_ended, model_module, reason}` and the watcher reconnects
  # with exponential backoff (500 ms doubling up to 30 s). Once the stream opens again, every
  # subscriber receives `{:chronicle_read_model_watch_resumed, model_module}` and the backoff resets.
  #
  # The watcher stops itself, closing the stream, once its last subscriber unsubscribes or exits.

  use GenServer, restart: :temporary

  alias Chronicle.Client
  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.ReadModels.{ReadModels, WatchRequest}

  @min_backoff 500
  @max_backoff 30_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc false
  @spec subscribe(pid(), pid()) :: {:ok, pid()}
  def subscribe(watcher, subscriber), do: GenServer.call(watcher, {:subscribe, subscriber})

  @doc false
  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(watcher, subscriber) do
    GenServer.call(watcher, {:unsubscribe, subscriber})
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)
    model_module = Keyword.fetch!(opts, :model_module)
    registry = Keyword.fetch!(opts, :registry)
    key = Keyword.fetch!(opts, :key)

    min_backoff = Keyword.get(opts, :min_backoff, @min_backoff)

    state = %{
      client: client,
      model_module: model_module,
      namespace: Keyword.get(opts, :namespace),
      event_sequence_id: Keyword.get(opts, :event_sequence_id, "event-log"),
      opener: Keyword.get(opts, :stream_opener, &default_opener/1),
      subscribers: %{},
      stream_pid: nil,
      stream_ref: nil,
      last_stream_error: nil,
      status: :starting,
      min_backoff: min_backoff,
      max_backoff: Keyword.get(opts, :max_backoff, @max_backoff),
      backoff: min_backoff
    }

    case Registry.register(registry, key, nil) do
      {:ok, _owner} -> {:ok, state}
      {:error, {:already_registered, _pid}} -> :ignore
    end
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    if Map.has_key?(state.subscribers, subscriber) do
      {:reply, {:ok, self()}, state}
    else
      ref = Process.monitor(subscriber)
      state = %{state | subscribers: Map.put(state.subscribers, subscriber, ref)}
      state = if state.stream_pid, do: state, else: start_stream(state)
      {:reply, {:ok, self()}, state}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    state = drop_subscriber(state, subscriber)

    if map_size(state.subscribers) == 0 do
      {:stop, :normal, :ok, close_stream(state)}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:chronicle_watcher_stream_started, state) do
    state =
      if state.status == :reconnecting do
        notify(state, {:chronicle_read_model_watch_resumed, state.model_module})
        %{state | backoff: state.min_backoff}
      else
        state
      end

    {:noreply, %{state | status: :connected}}
  end

  def handle_info({:chronicle_watcher_event, raw_changeset}, state) do
    changeset = Chronicle.ReadModels.decode_watch_changeset(state.model_module, raw_changeset)
    notify(state, {:chronicle_read_model_changed, state.model_module, changeset})
    {:noreply, state}
  end

  def handle_info({:chronicle_watcher_stream_error, reason}, state) do
    {:noreply, %{state | last_stream_error: reason}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{stream_ref: ref} = state) do
    reason = state.last_stream_error || :stream_closed
    notify(state, {:chronicle_read_model_watch_ended, state.model_module, reason})

    state = %{state | stream_pid: nil, stream_ref: nil, status: :reconnecting}
    Process.send_after(self(), :reconnect, state.backoff)
    {:noreply, %{state | backoff: next_backoff(state.backoff, state.max_backoff)}}
  end

  def handle_info(:reconnect, state), do: {:noreply, start_stream(state)}

  def handle_info({:DOWN, ref, :process, subscriber, _reason}, state) do
    if Map.get(state.subscribers, subscriber) == ref do
      state = drop_subscriber(state, subscriber)

      if map_size(state.subscribers) == 0 do
        {:stop, :normal, close_stream(state)}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp drop_subscriber(state, subscriber) do
    case Map.pop(state.subscribers, subscriber) do
      {nil, subscribers} ->
        %{state | subscribers: subscribers}

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        %{state | subscribers: subscribers}
    end
  end

  defp notify(state, message), do: Enum.each(Map.keys(state.subscribers), &send(&1, message))

  defp next_backoff(backoff, max_backoff), do: min(backoff * 2, max_backoff)

  defp start_stream(%{opener: opener} = state) do
    parent = self()
    {pid, ref} = spawn_monitor(fn -> run_stream(parent, opener, state) end)
    %{state | stream_pid: pid, stream_ref: ref, last_stream_error: nil}
  end

  defp close_stream(%{stream_pid: nil} = state), do: state

  defp close_stream(%{stream_pid: pid, stream_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :shutdown)
    %{state | stream_pid: nil, stream_ref: nil}
  end

  defp run_stream(parent, opener, state) do
    case opener.(state) do
      {:ok, reply_stream} ->
        send(parent, :chronicle_watcher_stream_started)

        Enum.each(reply_stream, fn
          {:ok, changeset} -> send(parent, {:chronicle_watcher_event, changeset})
          {:error, reason} -> send(parent, {:chronicle_watcher_stream_error, reason})
        end)

      {:error, reason} ->
        send(parent, {:chronicle_watcher_stream_error, reason})
    end
  end

  defp default_opener(state) do
    config = Client.config(state.client)

    with {:ok, channel} <- Connection.channel(config.connection) do
      request =
        struct(WatchRequest,
          EventStore: config.event_store,
          Namespace: state.namespace || config.namespace,
          ReadModelIdentifier: state.model_module.__chronicle_read_model__(:id),
          EventSequenceId: state.event_sequence_id
        )

      ReadModels.Stub.watch(channel, request)
    end
  end
end
