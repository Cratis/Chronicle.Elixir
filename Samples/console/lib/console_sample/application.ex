# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Application do
  @moduledoc false

  use Application

  alias ConsoleSample.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}
  alias ConsoleSample.ReadModels.Account
  alias ConsoleSample.Reactors.NotificationReactor
  alias ConsoleSample.Reducers.AccountReducer

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: connection_string(),
       event_store: "console-sample",
       event_types: [AccountOpened, FundsDeposited, FundsWithdrawn],
       reactors: [NotificationReactor],
       reducers: [AccountReducer],
       read_models: [Account]}
    ]

    opts = [strategy: :one_for_one, name: ConsoleSample.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Task.start(fn -> ConsoleSample.run_demo() end)

    {:ok, pid}
  end

  defp connection_string do
    System.get_env("CHRONICLE_CONNECTION_STRING") ||
      "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000?disableTls=true"
  end
end
