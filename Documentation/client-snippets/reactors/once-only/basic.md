```elixir
defmodule OnceOnlyOrderPlaced do
  use Chronicle.Events.EventType, id: "once-only-order-placed"

  defstruct [:order_id]
end

defmodule OnceOnlyOrderReactor do
  # The handler for OnceOnlyOrderPlaced runs when the event is first processed
  # and is skipped during replay.
  use Chronicle.Reactors.Reactor, once_only: [OnceOnlyOrderPlaced]

  @handles OnceOnlyOrderPlaced

  @impl true
  def handle(%OnceOnlyOrderPlaced{}, _context) do
    # Send the notification.
    :ok
  end
end
```
