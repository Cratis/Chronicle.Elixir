```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueEventTypeUserRegistered do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-event-type-user-registered"

  defstruct [:email, :display_name]

  unique_event_type()
end
```
