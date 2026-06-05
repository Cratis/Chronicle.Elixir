# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.Registrar do
  @moduledoc false

  use GenServer, restart: :permanent

  require Logger

  @retry_delay 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %{client: Keyword.fetch!(opts, :client)}
    send(self(), :register)
    {:ok, state}
  end

  @impl true
  def handle_info(:register, state) do
    case Chronicle.WebHooks.register_discovered(client: state.client) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "Chronicle webhook registration failed: #{inspect(reason)}, retrying in #{@retry_delay}ms"
        )

        Process.send_after(self(), :register, @retry_delay)
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}
end
