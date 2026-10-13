# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Watchdog do
  @moduledoc """
  Reconnects a client that has been stuck without being registered.

  A client normally goes `:disconnected` -> `:connected` -> `:registered`. If it stays short of
  `:registered` for longer than `unregistered_for` milliseconds - the kernel restarted, a
  registration keeps failing, the session was evicted and nothing noticed - the watchdog asks the
  connection to dial a fresh channel. That is what a hand-written supervisor-of-the-client
  watchdog used to do; enable it with the client option:

      {Chronicle.Client, watchdog: [unregistered_for: 60_000]}

  Options: `:unregistered_for` (milliseconds, default `60_000`) and `:check_every` (default a
  quarter of that). A reconnect is requested at most once per `unregistered_for` period.
  """

  use GenServer

  require Logger

  alias Chronicle.Connections.{Connection, Lifecycle}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    unregistered_for = Keyword.get(opts, :unregistered_for, 60_000)

    state = %{
      lifecycle: Keyword.fetch!(opts, :lifecycle),
      connection: Keyword.fetch!(opts, :connection),
      unregistered_for: unregistered_for,
      check_every: Keyword.get(opts, :check_every, max(div(unregistered_for, 4), 10)),
      since: now(),
      phase: :disconnected
    }

    Lifecycle.subscribe(state.lifecycle)
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, phase, _connection_id}, state) do
    since = if phase == :registered or phase != state.phase, do: now(), else: state.since
    {:noreply, %{state | phase: phase, since: since}}
  end

  def handle_info(:check, state) do
    state =
      if decide(state.phase, state.since, now(), state.unregistered_for) == :reconnect do
        Logger.warning(
          "Chronicle client has not been registered for #{state.unregistered_for}ms " <>
            "(phase: #{state.phase}); reconnecting"
        )

        Connection.reconnect(state.connection)
        %{state | since: now()}
      else
        state
      end

    schedule(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  @spec decide(atom(), integer(), integer(), pos_integer()) :: :ok | :reconnect
  def decide(:registered, _since, _now, _limit), do: :ok
  def decide(_phase, since, now, limit) when now - since >= limit, do: :reconnect
  def decide(_phase, _since, _now, _limit), do: :ok

  defp schedule(state), do: Process.send_after(self(), :check, state.check_every)
  defp now, do: System.monotonic_time(:millisecond)
end
