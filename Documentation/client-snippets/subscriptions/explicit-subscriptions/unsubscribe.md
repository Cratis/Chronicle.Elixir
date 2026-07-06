```elixir
defmodule MyApp.SubscriptionsExplicitUnsubscribe do
  def run do
    Chronicle.unsubscribe_from_event_store("orders-from-fulfillment")
  end
end
```
