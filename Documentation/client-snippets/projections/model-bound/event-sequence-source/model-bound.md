```elixir
defmodule MyApp.Events.MbEventSeqOrderPlaced do
  use Chronicle.Events.EventType, id: "mb-event-seq-order-placed"

  defstruct amount: 0.0
end

defmodule MyApp.ReadModels.MbEventSeqOrderSummary do
  use Chronicle.ReadModels.ReadModel, event_sequence: "custom-sequence"

  defstruct id: "", total_amount: 0.0

  # Takes the amount from each event, like the other clients' SetFrom mapping.
  from MyApp.Events.MbEventSeqOrderPlaced,
    set: [id: :event_source_id, total_amount: :amount]
end
```
