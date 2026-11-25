```elixir
defmodule MyApp.Events.SubscriptionsTypicalShipmentDispatched do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-typical-shipment-dispatched"

  defstruct [:order_id]
end

defmodule MyApp.Events.SubscriptionsTypicalStockAdjusted do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-typical-stock-adjusted"

  defstruct [:item_id, :delta]
end

defmodule MyApp.Events.SubscriptionsTypicalStockReserved do
  use Cratis.Chronicle.Events.EventType, id: "subscriptions-typical-stock-reserved"

  defstruct [:item_id, :quantity]
end

defmodule MyApp.SubscriptionsTypicalRegistration do
  @moduledoc false

  alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder

  alias MyApp.Events.{
    SubscriptionsTypicalShipmentDispatched,
    SubscriptionsTypicalStockAdjusted,
    SubscriptionsTypicalStockReserved
  }

  def register_subscriptions do
    :ok =
      Cratis.Chronicle.subscribe_to_event_store(
        "orders-from-fulfillment",
        "fulfillment-service",
        fn builder ->
          DefinitionBuilder.with_event_type(builder, SubscriptionsTypicalShipmentDispatched)
        end,
        []
      )

    :ok =
      Cratis.Chronicle.subscribe_to_event_store(
        "inventory-updates",
        "warehouse-service",
        fn builder ->
          builder
          |> DefinitionBuilder.with_event_type(SubscriptionsTypicalStockAdjusted)
          |> DefinitionBuilder.with_event_type(SubscriptionsTypicalStockReserved)
        end,
        []
      )
  end
end
```
