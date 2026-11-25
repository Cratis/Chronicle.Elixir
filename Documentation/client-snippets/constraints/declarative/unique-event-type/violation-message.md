```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeMessageProjectInitialized do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-event-type-message-project-initialized"
  defstruct []
end

defmodule MyApp.Constraints.ConstraintsUniqueEventTypeMessageProjectInitialization do
  use Cratis.Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsUniqueEventTypeMessageProjectInitialized,
    name: "ConstraintsUniqueEventTypeMessageProjectInitialization",
    message: "A project can only be initialized once."
end
```
