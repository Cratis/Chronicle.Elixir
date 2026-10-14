```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeNamedProjectInitialized do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-named-project-initialized"
  defstruct []
end

defmodule MyApp.Constraints.ConstraintsUniqueEventTypeNamedProjectInitialization do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsUniqueEventTypeNamedProjectInitialized,
    name: "UniqueProjectInitialization",
    message: "A project can only be initialized once."
end
```
