```elixir
defmodule MyApp.EventSequencesRedactForEventSourceWithTypes do
  alias MyApp.Events.OrderPlaced

  def redact_order_placed_events(event_source_id) do
    Chronicle.EventSequences.EventLog.redact_for_event_source(
      event_source_id,
      "Order data was captured in error",
      [OrderPlaced]
    )
  end
end
```
