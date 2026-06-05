# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: connection_string(), event_store: "TestStore", otp_app: :console_sample}
    ]

    opts = [strategy: :one_for_one, name: ConsoleSample.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Task.start(fn -> ConsoleSample.run() end)

    {:ok, pid}
  end

  defp connection_string do
    System.get_env("CHRONICLE_CONNECTION_STRING") ||
      "chronicle://localhost:35000?disableTls=true"
  end
end
