```elixir
defmodule MyApp.Events.TestingCollectionOrderPlaced do
  use Chronicle.Events.EventType, id: "testing-collection-order-placed"

  defstruct [:order_id]
end

defmodule MyApp.Events.TestingCollectionShipmentScheduled do
  use Chronicle.Events.EventType, id: "testing-collection-shipment-scheduled"

  defstruct [:order_id]
end

defmodule MyApp.Reactors.TestingCollectionShipmentReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{TestingCollectionOrderPlaced, TestingCollectionShipmentScheduled}

  @handles TestingCollectionOrderPlaced

  # A bare event in the returned side effect uses the triggering event's own
  # event source id.
  @impl true
  def handle(%TestingCollectionOrderPlaced{} = event, _context),
    do: {:ok, %TestingCollectionShipmentScheduled{order_id: event.order_id}}
end
```
