```elixir
defmodule MyApp.Events.TestingReadModelScenarioReducerOrderCreated do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-reducer-order-created"

  defstruct [:order_id]
end

defmodule MyApp.Events.TestingReadModelScenarioReducerItemAdded do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-reducer-item-added"

  defstruct [:price_in_cents]
end

defmodule MyApp.ReadModels.TestingReadModelScenarioReducerOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct order_id: nil, total_in_cents: 0
end

defmodule MyApp.Reducers.TestingReadModelScenarioReducerOrderSummaryReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.TestingReadModelScenarioReducerOrderSummary

  alias MyApp.Events.{
    TestingReadModelScenarioReducerItemAdded,
    TestingReadModelScenarioReducerOrderCreated
  }

  alias MyApp.ReadModels.TestingReadModelScenarioReducerOrderSummary

  @handles TestingReadModelScenarioReducerOrderCreated
  @handles TestingReadModelScenarioReducerItemAdded

  @impl true
  def reduce(%TestingReadModelScenarioReducerOrderCreated{order_id: order_id}, _model, _context),
    do: %TestingReadModelScenarioReducerOrderSummary{order_id: order_id, total_in_cents: 0}

  def reduce(%TestingReadModelScenarioReducerItemAdded{price_in_cents: price}, model, _context),
    do: %{model | total_in_cents: model.total_in_cents + price}
end

defmodule MyApp.TestingReadModelScenarioReducerExampleTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingReadModelScenarioReducerOrderCreated,
      MyApp.Events.TestingReadModelScenarioReducerItemAdded
    ],
    reducers: [MyApp.Reducers.TestingReadModelScenarioReducerOrderSummaryReducer]

  alias MyApp.Events.{
    TestingReadModelScenarioReducerItemAdded,
    TestingReadModelScenarioReducerOrderCreated
  }

  alias MyApp.Reducers.TestingReadModelScenarioReducerOrderSummaryReducer

  test "the reducer totals the item prices", %{chronicle: client} do
    order_id = "order-1"

    :ok =
      Chronicle.EventSequences.EventLog.append_many(
        order_id,
        [
          %TestingReadModelScenarioReducerOrderCreated{order_id: order_id},
          %TestingReadModelScenarioReducerItemAdded{price_in_cents: 999},
          %TestingReadModelScenarioReducerItemAdded{price_in_cents: 450}
        ],
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    {:ok, summary} =
      Chronicle.Testing.read_model(
        client,
        TestingReadModelScenarioReducerOrderSummaryReducer,
        order_id
      )

    assert summary.total_in_cents == 1449
  end
end
```
