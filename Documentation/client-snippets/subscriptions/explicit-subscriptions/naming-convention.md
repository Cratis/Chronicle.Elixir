```elixir
defmodule MyApp.Events.SubscriptionsExplicitStockAdjusted do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-explicit-stock-adjusted"

  defstruct [:item_id, :delta]
end

defmodule MyApp.SubscriptionsExplicitNamingConvention do
  alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias MyApp.Events.{SubscriptionsExplicitShipmentDispatched, SubscriptionsExplicitStockAdjusted}

  def run do
    # subscription-id format: {target}-from-{source}
    :ok =
      Cratis.Chronicle.subscribe_to_event_store(
        "orders-from-fulfillment",
        "fulfillment-service",
        fn builder -> DefinitionBuilder.with_event_type(builder, SubscriptionsExplicitShipmentDispatched) end,
        []
      )

    Cratis.Chronicle.subscribe_to_event_store(
      "inventory-from-warehouse",
      "warehouse-service",
      fn builder -> DefinitionBuilder.with_event_type(builder, SubscriptionsExplicitStockAdjusted) end,
      []
    )
  end
end
```
