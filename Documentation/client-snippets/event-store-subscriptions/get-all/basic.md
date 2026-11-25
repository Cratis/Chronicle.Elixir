```elixir
defmodule MyApp.EventStoreSubscriptionsGetAll do
  def list_subscriptions do
    Cratis.Chronicle.EventStoreSubscriptions.get_all()
  end
end
```
