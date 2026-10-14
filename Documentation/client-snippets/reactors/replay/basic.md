```elixir
defmodule ReplayAwareOrderPlaced do
  use Chronicle.Events.EventType, id: "replay-aware-order-placed"

  defstruct [:order_id]
end

defmodule ReplayAwareOrderReactor do
  use Chronicle.Reactors.Reactor

  @handles ReplayAwareOrderPlaced

  # Runs as the event happens.
  @impl true
  def handle(%ReplayAwareOrderPlaced{}, _context), do: :ok

  # Runs instead of handle/2 while the observer is replaying.
  @impl true
  def handle_replay(%ReplayAwareOrderPlaced{}, _context), do: :ok
end
```
