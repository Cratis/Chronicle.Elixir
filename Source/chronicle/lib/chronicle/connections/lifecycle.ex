# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Lifecycle do
  @moduledoc """
  Tracks the Chronicle connection lifecycle and broadcasts phase changes.

  `Lifecycle` is the single source of truth for whether a client is connected
  and for the `connection_id` used on the wire. It mirrors the C# client's
  `IConnectionLifecycle`: there is one lifecycle per `Chronicle.Client`, every
  artifact that needs the connection (the registration coordinator, reactors,
  reducers, seeders, webhook and subscription registrars) subscribes to it, and
  the connection is driven through a small set of phase transitions.

  ## Phases

  The connection moves through three ordered phases:

    * `:disconnected` — no live session with the kernel.
    * `:connected` — the session handshake completed (the kernel acknowledged
      the `connection_id` via its first keepalive). The channel can carry calls.
    * `:registered` — the registration coordinator has registered the base
      artifacts (event store, event types, read models, constraints,
      projections). Observers may now safely register their observation
      streams, and seeders may run.

  Splitting `:connected` from `:registered` is what keeps reducers and reactors
  from racing ahead of their server-side definitions — they wait for
  `:registered`, never merely `:connected`.

  ## connection_id

  The lifecycle owns the `connection_id`. It is adopted on `connected/2` and
  **rotated on `disconnected/1`**, so every reconnect uses a fresh id, exactly
  like the C# client. Because the id lives in one place, the value used in the
  session handshake and in every reactor/reducer registration is guaranteed
  consistent for a given connection epoch.

  ## Subscribing

  Subscribers call `subscribe/1`, which returns the current `{phase,
  connection_id}` snapshot *and* delivers it as a message. This closes the race
  where a subscriber starts after a phase change has already happened: it always
  learns the current phase immediately, whether it subscribed before or after
  the transition. Subsequent transitions arrive as messages of the form:

      {:chronicle_lifecycle, phase, connection_id}

  where `phase` is `:connected`, `:registered`, or `:disconnected`.
  """

  use GenServer

  @type phase :: :disconnected | :connected | :registered

  @phase_rank %{disconnected: 0, connected: 1, registered: 2}

  @doc """
  Starts a lifecycle process.

  ## Options

    * `:client` — the owning client name; the process is registered as
      `:"<client>.Lifecycle"`.
    * `:name` — an explicit registered name (overrides `:client`). When neither
      is given the process is unnamed and callers use the returned pid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case name_from(opts) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Returns the registered lifecycle name for a client.
  """
  @spec name_for(atom()) :: atom()
  def name_for(client), do: :"#{client}.Lifecycle"

  @doc """
  Subscribes the calling process to lifecycle phase changes.

  Returns `{:ok, phase, connection_id}` with the current snapshot and also sends
  the caller a `{:chronicle_lifecycle, phase, connection_id}` message so the
  subscribe-time and transition-time code paths are identical.
  """
  @spec subscribe(GenServer.server()) :: {:ok, phase(), String.t()}
  def subscribe(lifecycle) do
    GenServer.call(lifecycle, :subscribe)
  end

  @doc """
  Returns the current phase.
  """
  @spec phase(GenServer.server()) :: phase()
  def phase(lifecycle), do: GenServer.call(lifecycle, :phase)

  @doc """
  Returns the current connection id.
  """
  @spec connection_id(GenServer.server()) :: String.t()
  def connection_id(lifecycle), do: GenServer.call(lifecycle, :connection_id)

  @doc """
  Transitions to `:connected`, adopting the given `connection_id`.

  Called by `Chronicle.Connections.Session` on the first server keepalive.
  """
  @spec connected(GenServer.server(), String.t()) :: :ok
  def connected(lifecycle, connection_id) do
    GenServer.cast(lifecycle, {:connected, connection_id})
  end

  @doc """
  Transitions to `:registered`.

  Called by the registration coordinator once the base artifacts are registered
  with the kernel.
  """
  @spec registered(GenServer.server()) :: :ok
  def registered(lifecycle), do: GenServer.cast(lifecycle, :registered)

  @doc """
  Transitions to `:disconnected` and rotates the `connection_id`.

  Called by `Chronicle.Connections.Session` when the session is lost.
  """
  @spec disconnected(GenServer.server()) :: :ok
  def disconnected(lifecycle), do: GenServer.cast(lifecycle, :disconnected)

  @doc """
  Blocks until the connection reaches at least `target_phase`.

  Returns `:ok` immediately if the current phase is already at or beyond the
  target, otherwise waits up to `timeout` milliseconds. Returns `{:error,
  :timeout}` if the target is not reached in time.
  """
  @spec wait_until(GenServer.server(), phase(), timeout()) :: :ok | {:error, :timeout}
  def wait_until(lifecycle, target_phase, timeout \\ 30_000) do
    call_timeout =
      case timeout do
        :infinity -> :infinity
        ms when is_integer(ms) -> ms + 1_000
      end

    GenServer.call(lifecycle, {:wait_until, target_phase, timeout}, call_timeout)
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       phase: :disconnected,
       connection_id: generate_connection_id(),
       subscribers: %{},
       waiters: []
     }}
  end

  @impl true
  def handle_call(:subscribe, {pid, _tag}, state) do
    ref = Process.monitor(pid)
    state = put_in(state.subscribers[ref], pid)
    send(pid, {:chronicle_lifecycle, state.phase, state.connection_id})
    {:reply, {:ok, state.phase, state.connection_id}, state}
  end

  def handle_call(:phase, _from, state), do: {:reply, state.phase, state}

  def handle_call(:connection_id, _from, state), do: {:reply, state.connection_id, state}

  def handle_call({:wait_until, target_phase, timeout}, from, state) do
    if reached?(state.phase, target_phase) do
      {:reply, :ok, state}
    else
      timer = schedule_wait_timeout(from, timeout)
      {:noreply, %{state | waiters: [{from, target_phase, timer} | state.waiters]}}
    end
  end

  @impl true
  def handle_cast({:connected, connection_id}, state) do
    state = %{state | phase: :connected, connection_id: connection_id}
    broadcast(state)
    {:noreply, release_waiters(state)}
  end

  def handle_cast(:registered, state) do
    state = %{state | phase: :registered}
    broadcast(state)
    {:noreply, release_waiters(state)}
  end

  def handle_cast(:disconnected, state) do
    broadcast(%{state | phase: :disconnected})
    {:noreply, %{state | phase: :disconnected, connection_id: generate_connection_id()}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, update_in(state.subscribers, &Map.delete(&1, ref))}
  end

  def handle_info({:wait_timeout, from}, state) do
    {matches, remaining} = Enum.split_with(state.waiters, fn {f, _, _} -> f == from end)

    Enum.each(matches, fn {f, _, _} -> GenServer.reply(f, {:error, :timeout}) end)
    {:noreply, %{state | waiters: remaining}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp broadcast(%{subscribers: subscribers, phase: phase, connection_id: connection_id}) do
    Enum.each(subscribers, fn {_ref, pid} ->
      send(pid, {:chronicle_lifecycle, phase, connection_id})
    end)
  end

  defp release_waiters(%{phase: phase, waiters: waiters} = state) do
    {ready, pending} =
      Enum.split_with(waiters, fn {_from, target, _timer} -> reached?(phase, target) end)

    Enum.each(ready, fn {from, _target, timer} ->
      cancel_timer(timer)
      GenServer.reply(from, :ok)
    end)

    %{state | waiters: pending}
  end

  defp reached?(current_phase, target_phase) do
    Map.fetch!(@phase_rank, current_phase) >= Map.fetch!(@phase_rank, target_phase)
  end

  defp schedule_wait_timeout(_from, :infinity), do: nil

  defp schedule_wait_timeout(from, timeout) when is_integer(timeout) do
    Process.send_after(self(), {:wait_timeout, from}, timeout)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp name_from(opts) do
    cond do
      name = opts[:name] -> name
      client = opts[:client] -> name_for(client)
      true -> nil
    end
  end

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
