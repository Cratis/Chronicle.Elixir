```elixir
defmodule MyApp.Events.SubscriptionsStartupShipmentDispatched do
  use Chronicle.Events.EventType, id: "subscriptions-startup-shipment-dispatched"

  defstruct [:order_id]
end

defmodule MyApp.Events.SubscriptionsStartupStockAdjusted do
  use Chronicle.Events.EventType, id: "subscriptions-startup-stock-adjusted"

  defstruct [:item_id, :delta]
end

defmodule MyApp.SubscriptionsStartupApplication do
  use Application

  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias MyApp.Events.{SubscriptionsStartupShipmentDispatched, SubscriptionsStartupStockAdjusted}

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: "chronicle://localhost:35000",
       event_store: "quickstart"}
    ]

    supervisor = Supervisor.start_link(children, strategy: :one_for_one)

    # Safe to call on every application startup — Chronicle treats a repeated
    # subscription id as idempotent and creates no duplicate.
    :ok =
      Chronicle.subscribe_to_event_store(
        "orders-from-fulfillment",
        "fulfillment-service",
        fn builder ->
          DefinitionBuilder.with_event_type(builder, SubscriptionsStartupShipmentDispatched)
        end,
        []
      )

    :ok =
      Chronicle.subscribe_to_event_store(
        "inventory-from-warehouse",
        "warehouse-service",
        fn builder ->
          DefinitionBuilder.with_event_type(builder, SubscriptionsStartupStockAdjusted)
        end,
        []
      )

    supervisor
  end
end
```
