# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.ClientOperationsTest do
  use ExUnit.Case, async: false

  defmodule Account do
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct id: ""
  end

  defmodule Watcher do
    use Cratis.Chronicle.ReadModels.Reactor, model: Account
  end

  # A client that never reaches a kernel: the supervision tree must still come up with every
  # optional child, and the registration API must work against it.
  setup do
    name = :"operations_client_#{System.unique_integer([:positive])}"

    {:ok, client} =
      Cratis.Chronicle.Client.start_link(
        name: name,
        discover: false,
        connection_string: "chronicle://localhost:1?disableTls=true",
        read_model_reactors: [Watcher],
        observer_lag: [interval: 60_000],
        watchdog: true,
        registration: [initial_delay: 50, max_attempts: 2]
      )

    %{name: name, client: client}
  end

  test "starts with every optional child", %{client: client} do
    modules =
      client
      |> Supervisor.which_children()
      |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

    assert Cratis.Chronicle.Observers.Lag.Reporter in modules
    assert Cratis.Chronicle.Connections.Watchdog in modules
    assert {Cratis.Chronicle.ReadModels.Reactors.Handler, Watcher} in modules
  end

  test "registration status is available while the kernel is unreachable", %{name: name} do
    assert %{state: state} = Cratis.Chronicle.Client.registration_status(name)
    assert state in [:pending, :registering]
    assert Cratis.Chronicle.Client.await_registration(name, 50) == {:error, :timeout}
  end

  test "discovery_report/1 is available as soon as the client starts", %{name: name} do
    report = Cratis.Chronicle.Client.discovery_report(name)
    assert report.has_run
    assert Cratis.Chronicle.Discovery.Report.of_kind(report, :read_model) == []
  end

  test "identity_drift/1 is empty while the kernel is unreachable", %{name: name} do
    assert Cratis.Chronicle.Client.identity_drift(name) == []
  end
end
