# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Seeding.Runner do
  @moduledoc false

  # Runs the configured seeders once the connection lifecycle reaches the
  # `:registered` phase — i.e. after the event store, event types and observers
  # are registered with the kernel. This replaces the previous fire-and-forget
  # spawn that ran on a fixed delay and failed with `:not_connected` when the
  # connection was not yet ready.
  #
  # Seeding is idempotent: `Chronicle.Seeding.register/1` skips event sources
  # that already have events (`has_events_for?/2`), so re-running on reconnect is
  # a cheap no-op. On failure the runner retries with a bounded delay.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.Lifecycle

  @retry_delay 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %{
      client: Keyword.fetch!(opts, :client),
      connection: Keyword.fetch!(opts, :connection),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.fetch!(opts, :namespace),
      seeders: Keyword.get(opts, :seeders, []),
      lifecycle: Keyword.get(opts, :lifecycle),
      has_events_for: Keyword.get(opts, :has_events_for),
      append_many: Keyword.get(opts, :append_many),
      retry_timer: nil
    }

    if state.lifecycle, do: Lifecycle.subscribe(state.lifecycle)

    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, :registered, _connection_id}, state) do
    cancel_timer(state.retry_timer)
    {:noreply, run_seeders(%{state | retry_timer: nil})}
  end

  def handle_info({:chronicle_lifecycle, _phase, _connection_id}, state) do
    {:noreply, state}
  end

  def handle_info(:seed, state) do
    {:noreply, run_seeders(%{state | retry_timer: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_seeders(%{seeders: []} = state), do: state

  defp run_seeders(state) do
    Logger.info("Executing #{length(state.seeders)} seeder(s)")

    builder =
      %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.Events.EventTypes,
        connection: state.connection,
        event_store: state.event_store,
        namespace: state.namespace,
        client: state.client,
        has_events_for: state.has_events_for,
        append_many: state.append_many
      }

    case builder |> Chronicle.Seeding.discover(state.seeders) |> Chronicle.Seeding.register() do
      :ok ->
        Logger.info("Seeding completed")
        state

      {:error, reason} ->
        Logger.warning("Seeding failed: #{inspect(reason)}, retrying in #{@retry_delay}ms")
        %{state | retry_timer: Process.send_after(self(), :seed, @retry_delay)}
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
