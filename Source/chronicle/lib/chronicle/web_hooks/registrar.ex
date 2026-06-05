# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.Registrar do
  @moduledoc false

  # Registers discoverable webhooks once the connection lifecycle reaches the
  # `:registered` phase, and re-registers on every reconnect. Replaces the
  # previous blind retry-from-start loop.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.Lifecycle

  @retry_delay 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    state = %{
      client: client,
      lifecycle: Keyword.get(opts, :lifecycle),
      register_fun:
        Keyword.get(opts, :register_fun, fn ->
          Chronicle.WebHooks.register_discovered(client: client)
        end),
      retry_timer: nil
    }

    if state.lifecycle do
      Lifecycle.subscribe(state.lifecycle)
    else
      send(self(), :register)
    end

    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, :registered, _connection_id}, state) do
    cancel_timer(state.retry_timer)
    send(self(), :register)
    {:noreply, %{state | retry_timer: nil}}
  end

  def handle_info({:chronicle_lifecycle, :disconnected, _connection_id}, state) do
    cancel_timer(state.retry_timer)
    {:noreply, %{state | retry_timer: nil}}
  end

  def handle_info({:chronicle_lifecycle, _phase, _connection_id}, state) do
    {:noreply, state}
  end

  def handle_info(:register, state) do
    case state.register_fun.() do
      :ok ->
        {:noreply, %{state | retry_timer: nil}}

      {:error, reason} ->
        Logger.warning(
          "Chronicle webhook registration failed: #{inspect(reason)}, retrying in #{@retry_delay}ms"
        )

        timer = Process.send_after(self(), :register, @retry_delay)
        {:noreply, %{state | retry_timer: timer}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
