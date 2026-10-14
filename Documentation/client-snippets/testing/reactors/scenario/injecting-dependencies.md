```elixir
defmodule MyApp.Events.TestingReactorScenarioOrderShipped do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-order-shipped"

  defstruct [:order_id, :carrier]
end

defmodule MyApp.TestingReactorScenarioOrderRepository do
  @callback mark_as_shipped(String.t()) :: :ok
end

defmodule MyApp.Reactors.TestingReactorScenarioOrderReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingReactorScenarioOrderShipped

  @handles TestingReactorScenarioOrderShipped

  # The dependency is looked up when the event is handled, not compiled in.
  @impl true
  def handle(%TestingReactorScenarioOrderShipped{order_id: order_id}, _context) do
    repository = Application.fetch_env!(:my_app, :testing_reactor_scenario_order_repository)
    repository.mark_as_shipped(order_id)
  end
end

defmodule MyApp.TestingReactorScenarioRecordingOrderRepository do
  @behaviour MyApp.TestingReactorScenarioOrderRepository

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def shipped, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def mark_as_shipped(order_id), do: Agent.update(__MODULE__, &[order_id | &1])
end

defmodule MyApp.TestingReactorScenarioInjectingDependenciesTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReactorScenarioOrderShipped],
    reactors: [MyApp.Reactors.TestingReactorScenarioOrderReactor]

  alias MyApp.Events.TestingReactorScenarioOrderShipped
  alias MyApp.TestingReactorScenarioRecordingOrderRepository, as: OrderRepository

  setup do
    {:ok, _repository} = OrderRepository.start_link()
    Application.put_env(:my_app, :testing_reactor_scenario_order_repository, OrderRepository)
    on_exit(fn -> Application.delete_env(:my_app, :testing_reactor_scenario_order_repository) end)
  end

  test "the reactor marks the order as shipped through its dependency", %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "order-123",
        %TestingReactorScenarioOrderShipped{order_id: "order-123", carrier: "FedEx"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    assert OrderRepository.shipped() == ["order-123"]
  end
end
```
