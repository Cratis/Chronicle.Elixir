```elixir
defmodule MyApp.Events.SubscriptionsExplicitStockAdjusted do
  use Chronicle.Events.EventType, id: "subscriptions-explicit-stock-adjusted"

  defstruct [:item_id, :delta]
end

defmodule MyApp.SubscriptionsExplicitNamingConvention do
  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias MyApp.Events.{SubscriptionsExplicitShipmentDispatched, SubscriptionsExplicitStockAdjusted}

  def run do
    # subscription-id format: {target}-from-{source}
    :ok =
      Chronicle.subscribe_to_event_store(
        "orders-from-fulfillment",
        "fulfillment-service",
        fn builder -> DefinitionBuilder.with_event_type(builder, SubscriptionsExplicitShipmentDispatched) end,
        []
      )

    Chronicle.subscribe_to_event_store(
      "inventory-from-warehouse",
      "warehouse-service",
      fn builder -> DefinitionBuilder.with_event_type(builder, SubscriptionsExplicitStockAdjusted) end,
      []
    )
  end
end
```
