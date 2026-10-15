```elixir
defmodule MyApp.Events.ClosingEventsReportDelivered do
  use Chronicle.Events.EventType, id: "closing-events-report-delivered"

  defstruct [:recipient]

  # Appending this event closes the stream scope made of the event source and the stream type.
  closes_stream dimensions: [:event_source_id, :event_stream_type]
end
```
