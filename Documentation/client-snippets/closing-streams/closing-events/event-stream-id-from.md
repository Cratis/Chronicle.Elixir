```elixir
defmodule MyApp.Events.ClosingEventsBooksReopened do
  use Chronicle.Events.EventType, id: "closing-events-books-reopened"

  defstruct [:period, :reason]
end

defmodule MyApp.Events.ClosingEventsBooksClosed do
  use Chronicle.Events.EventType, id: "closing-events-books-closed"

  defstruct [:period, :closing_balance]

  # The stream id comes from the event's own period field, and the reopening event lifts the closure.
  closes_stream event_stream_id_from: :period,
                reopened_by: [MyApp.Events.ClosingEventsBooksReopened]
end
```
