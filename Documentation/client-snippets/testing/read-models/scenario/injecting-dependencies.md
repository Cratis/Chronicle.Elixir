```elixir
defmodule MyApp.Events.TestingReadModelScenarioOrderCreated do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-order-created"

  defstruct [:order_id]
end

defmodule MyApp.ReadModels.TestingReadModelScenarioOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct order_id: nil, total_in_cents: 0
end

defmodule MyApp.TestingReadModelScenarioPricingService do
  @callback get_base_price() :: non_neg_integer()
end

defmodule MyApp.Reducers.TestingReadModelScenarioOrderSummaryReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.TestingReadModelScenarioOrderSummary

  alias MyApp.Events.TestingReadModelScenarioOrderCreated
  alias MyApp.ReadModels.TestingReadModelScenarioOrderSummary

  @handles TestingReadModelScenarioOrderCreated

  @impl true
  def reduce(%TestingReadModelScenarioOrderCreated{order_id: order_id}, _model, _context) do
    pricing = Application.fetch_env!(:my_app, :testing_read_model_scenario_pricing)

    %TestingReadModelScenarioOrderSummary{
      order_id: order_id,
      total_in_cents: pricing.get_base_price()
    }
  end
end

defmodule MyApp.TestingReadModelScenarioFixedPricing do
  @behaviour MyApp.TestingReadModelScenarioPricingService

  @impl true
  def get_base_price, do: 2500
end

defmodule MyApp.TestingReadModelScenarioInjectingDependenciesTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingReadModelScenarioOrderCreated],
    reducers: [MyApp.Reducers.TestingReadModelScenarioOrderSummaryReducer]

  alias MyApp.Events.TestingReadModelScenarioOrderCreated
  alias MyApp.Reducers.TestingReadModelScenarioOrderSummaryReducer
  alias MyApp.TestingReadModelScenarioFixedPricing

  setup do
    Application.put_env(:my_app, :testing_read_model_scenario_pricing, TestingReadModelScenarioFixedPricing)
    on_exit(fn -> Application.delete_env(:my_app, :testing_read_model_scenario_pricing) end)
  end

  test "the reducer uses the injected pricing service", %{chronicle: client} do
    :ok =
      Chronicle.EventSequences.EventLog.append(
        "order-1",
        %TestingReadModelScenarioOrderCreated{order_id: "order-1"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    {:ok, summary} =
      Chronicle.Testing.read_model(client, TestingReadModelScenarioOrderSummaryReducer, "order-1")

    assert summary.total_in_cents == 2500
  end
end
```
