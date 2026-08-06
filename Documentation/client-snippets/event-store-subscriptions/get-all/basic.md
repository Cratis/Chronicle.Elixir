```elixir
defmodule MyApp.EventStoreSubscriptionsGetAll do
  def list_subscriptions do
    Chronicle.EventStoreSubscriptions.get_all()
  end
end
```
