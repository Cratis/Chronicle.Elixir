```elixir
defmodule MyApp.Events.ConstraintsPersonAliasedTo do
  use Chronicle.Events.EventType, id: "constraints-person-aliased-to"
  defstruct target: ""
end

defmodule MyApp.Events.ConstraintsPersonErased do
  use Chronicle.Events.EventType, id: "constraints-person-erased"
  defstruct []
end

# Both declarations share one constraint name, so they become a single constraint: at most
# one event drawn from {ConstraintsPersonAliasedTo, ConstraintsPersonErased} per person. A
# person merged away can no longer be erased, and neither event can occur twice.
defmodule MyApp.Constraints.ConstraintsPersonTerminalOutcome do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsPersonAliasedTo,
    name: "PersonTerminal",
    message: "This person already has a terminal outcome."

  unique_event_type MyApp.Events.ConstraintsPersonErased,
    name: "PersonTerminal",
    message: "This person already has a terminal outcome."
end
```
