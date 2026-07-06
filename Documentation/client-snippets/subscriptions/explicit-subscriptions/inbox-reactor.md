```elixir
defmodule MyApp.Events.SubscriptionsExplicitOrderPlaced do
  use Chronicle.Events.EventType, id: "subscriptions-explicit-order-placed"

  defstruct [:order_id, :amount]
end

defmodule MyApp.Reactors.SubscriptionsExplicitIncomingOrdersReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.SubscriptionsExplicitOrderPlaced

  @handles SubscriptionsExplicitOrderPlaced

  @impl true
  def handle(%SubscriptionsExplicitOrderPlaced{}, _context), do: :ok
end
```
