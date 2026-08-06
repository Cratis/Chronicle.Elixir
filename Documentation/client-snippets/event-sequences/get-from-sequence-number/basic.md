```elixir
defmodule MyApp.EventSequencesGetFromSequenceNumber do
  alias MyApp.Events.OrderPlaced

  def events_since(sequence_number, event_source_id) do
    Chronicle.EventSequences.EventLog.get_from_sequence_number(sequence_number,
      event_source_id: event_source_id,
      event_types: [OrderPlaced]
    )
  end
end
```
