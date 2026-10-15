```elixir
defmodule MyApp.Events.ClosingEventsVersionReinstated do
  use Chronicle.Events.EventType, id: "closing-events-version-reinstated"

  defstruct [:version]
end

# The Elixir client declares a closing event on the event type itself. Declarations
# that share a name merge into one constraint.
defmodule MyApp.Events.ClosingEventsVersionSuperseded do
  use Chronicle.Events.EventType, id: "closing-events-version-superseded"

  defstruct [:version]

  closes_stream name: "close-superseded-version",
                dimensions: [:event_source_id],
                event_stream_id_from: :version,
                reopened_by: [MyApp.Events.ClosingEventsVersionReinstated]
end
```
