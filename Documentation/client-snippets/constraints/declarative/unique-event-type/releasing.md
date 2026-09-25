```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeShiftStarted do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-shift-started"

  unique_event_type(name: "OneOpenShift")

  defstruct location: ""
end

defmodule MyApp.Events.ConstraintsUniqueEventTypeShiftEnded do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-shift-ended"

  remove_constraint "OneOpenShift"

  defstruct []
end
```
