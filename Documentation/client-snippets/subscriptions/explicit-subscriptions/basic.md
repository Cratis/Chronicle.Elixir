```elixir
defmodule MyApp.Events.SubscriptionsExplicitShipmentDispatched do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-explicit-shipment-dispatched"

  defstruct [:order_id]
end

defmodule MyApp.SubscriptionsExplicitBasic do
  alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias MyApp.Events.SubscriptionsExplicitShipmentDispatched

  def run do
    Cratis.Chronicle.subscribe_to_event_store(
      "orders-from-fulfillment",
      "fulfillment-service",
      fn builder -> DefinitionBuilder.with_event_type(builder, SubscriptionsExplicitShipmentDispatched) end,
      []
    )
  end
end
```
