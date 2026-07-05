```elixir
defmodule MyApp.SubscriptionsExplicitNoFilter do
  def run do
    # All events from fulfillment-service outbox will be forwarded
    Chronicle.subscribe_to_event_store("all-fulfillment-events", "fulfillment-service", [])
  end
end
```
