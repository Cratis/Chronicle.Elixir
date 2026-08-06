```elixir
defmodule MyApp.EventSequencesFilters do
  def audit_trail_events(event_source_id) do
    Chronicle.EventSequences.EventLog.get_for_event_source(event_source_id,
      event_stream_type: "audit-trail",
      event_stream_id: "2024"
    )
  end
end
```
