```elixir
defmodule MyApp.Events.GettingStateInventoryAdjusted do
  use Chronicle.Events.EventType, id: "getting-state-inventory-adjusted"

  defstruct sku: "", delta: 0
end

defmodule MyApp.Events.GettingStateInventoryReserved do
  use Chronicle.Events.EventType, id: "getting-state-inventory-reserved"

  defstruct sku: "", quantity: 0
end

defmodule MyApp.GettingStateInventoryCheckpoint do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{GettingStateInventoryAdjusted, GettingStateInventoryReserved}

  def capture_for(inventory_id) do
    # Scopes the tail to this event source and these event types.
    EventLog.get_tail_sequence_number(inventory_id,
      event_types: [GettingStateInventoryAdjusted, GettingStateInventoryReserved]
    )
  end
end
```
