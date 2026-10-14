```elixir
defmodule MyApp.Events.ExplicitIdOrderPlaced do
  use Chronicle.Events.EventType, id: "explicit-id-order-placed"

  defstruct []
end

defmodule MyApp.Reactors.SendWelcomeEmail do
  # For an already deployed reactor, use its existing stored observer id here.
  use Chronicle.Reactors.Reactor, id: "MyApp.Orders.SendWelcomeEmail"

  alias MyApp.Events.ExplicitIdOrderPlaced

  @handles ExplicitIdOrderPlaced

  # Keep the existing event handlers unchanged.
  @impl true
  def handle(%ExplicitIdOrderPlaced{}, _context), do: :ok
end
```
