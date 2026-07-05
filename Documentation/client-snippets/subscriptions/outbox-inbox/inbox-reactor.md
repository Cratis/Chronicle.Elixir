```elixir
defmodule MyApp.Events.SubscriptionsOutboxInboxOrderPlaced do
  use Chronicle.Events.EventType, id: "subscriptions-outbox-inbox-order-placed"

  defstruct [:order_id]
end

defmodule MyApp.Reactors.SubscriptionsOutboxInboxIncomingOrdersReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.SubscriptionsOutboxInboxOrderPlaced

  @handles SubscriptionsOutboxInboxOrderPlaced

  @impl true
  def handle(%SubscriptionsOutboxInboxOrderPlaced{}, _context) do
    # Handles OrderPlaced events from any subscribed source event store
    :ok
  end
end
```
