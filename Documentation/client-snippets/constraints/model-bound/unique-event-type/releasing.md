```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueEventTypeUserRemoved do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-event-type-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueUser")
end
```
