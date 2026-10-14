```elixir
defmodule MyApp.Events.TestingScenarioManyItemAddedToCart do
  use Chronicle.Events.EventType, id: "testing-scenario-many-item-added-to-cart"

  defstruct [:item_id]
end

defmodule MyApp.Events.TestingScenarioManyItemQuantityAdjusted do
  use Chronicle.Events.EventType, id: "testing-scenario-many-item-quantity-adjusted"

  defstruct [:item_id, :quantity]
end

defmodule MyApp.TestingScenarioAppendManyTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingScenarioManyItemAddedToCart, MyApp.Events.TestingScenarioManyItemQuantityAdjusted]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingScenarioManyItemAddedToCart, TestingScenarioManyItemQuantityAdjusted}

  test "several events are appended atomically", %{chronicle: client} do
    cart_id = "cart-#{System.unique_integer([:positive])}"

    {:ok, result} =
      EventLog.append_many_with_result(
        cart_id,
        [
          %TestingScenarioManyItemAddedToCart{item_id: "item-1"},
          %TestingScenarioManyItemAddedToCart{item_id: "item-2"},
          %TestingScenarioManyItemQuantityAdjusted{item_id: "item-1", quantity: 3}
        ],
        client: client
      )

    assert result.success?
    assert result.sequence_numbers == [0, 1, 2]
  end
end
```
