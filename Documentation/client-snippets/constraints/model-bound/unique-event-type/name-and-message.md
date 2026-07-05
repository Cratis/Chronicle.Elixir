```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueEventTypeNamedUserRegistered do
  use Chronicle.Events.EventType,
    id: "constraints-model-bound-unique-event-type-named-user-registered"

  defstruct [:email, :display_name]

  # Elixir supports a custom constraint name, but not a custom violation message.
  unique_event_type(name: "UniqueUser")
end
```
