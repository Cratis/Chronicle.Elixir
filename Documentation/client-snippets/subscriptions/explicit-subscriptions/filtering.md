```elixir
defmodule MyApp.Events.SubscriptionsExplicitStockReserved do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-explicit-stock-reserved"

  defstruct [:item_id, :quantity]
end

defmodule MyApp.SubscriptionsExplicitFiltering do
  alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias MyApp.Events.{SubscriptionsExplicitStockAdjusted, SubscriptionsExplicitStockReserved}

  def run do
    Cratis.Chronicle.subscribe_to_event_store(
      "inventory-updates",
      "warehouse-service",
      fn builder ->
        builder
        |> DefinitionBuilder.with_event_type(SubscriptionsExplicitStockAdjusted)
        |> DefinitionBuilder.with_event_type(SubscriptionsExplicitStockReserved)
      end,
      []
    )
  end
end
```
