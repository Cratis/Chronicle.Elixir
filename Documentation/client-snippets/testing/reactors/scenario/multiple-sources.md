```elixir
defmodule MyApp.Events.TestingReactorScenarioTenantActivated do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-tenant-activated"

  defstruct [:tenant_id]
end

defmodule MyApp.TestingReactorScenarioSyncService do
  @callback sync_tenant(String.t()) :: :ok
end

defmodule MyApp.Reactors.TestingReactorScenarioTenantSyncReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingReactorScenarioTenantActivated

  @handles TestingReactorScenarioTenantActivated

  @impl true
  def handle(%TestingReactorScenarioTenantActivated{tenant_id: tenant_id}, _context) do
    Application.fetch_env!(:my_app, :testing_reactor_scenario_sync_service).sync_tenant(tenant_id)
  end
end

defmodule MyApp.TestingReactorScenarioRecordingSyncService do
  @behaviour MyApp.TestingReactorScenarioSyncService

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def sync_tenant(tenant_id), do: Agent.update(__MODULE__, &[tenant_id | &1])
end

defmodule MyApp.TestingReactorScenarioMultipleSourcesTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReactorScenarioTenantActivated],
    reactors: [MyApp.Reactors.TestingReactorScenarioTenantSyncReactor]

  alias MyApp.Events.TestingReactorScenarioTenantActivated
  alias MyApp.TestingReactorScenarioRecordingSyncService, as: SyncService

  setup do
    {:ok, _service} = SyncService.start_link()
    Application.put_env(:my_app, :testing_reactor_scenario_sync_service, SyncService)
    on_exit(fn -> Application.delete_env(:my_app, :testing_reactor_scenario_sync_service) end)
  end

  test "events from different event sources are all handled", %{chronicle: client} do
    # Events from two different tenants
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "tenant-A",
        %TestingReactorScenarioTenantActivated{tenant_id: "tenant-A"},
        client: client
      )

    :ok =
      Chronicle.EventSequences.EventLog.append(
        "tenant-B",
        %TestingReactorScenarioTenantActivated{tenant_id: "tenant-B"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    # Both activations should have been handled
    assert SyncService.calls() == ["tenant-A", "tenant-B"]
  end
end
```
