```elixir
defmodule MyApp.Reactors.NamedOrderNotificationsReactor do
  use Chronicle.Reactors.Reactor, id: "order-notifications"

  alias MyApp.Events.ReactorOrderPlaced

  @handles ReactorOrderPlaced

  @impl true
  def handle(%ReactorOrderPlaced{}, _context), do: :ok
end
```
