```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueEventTypeUserRemoved do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-event-type-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueUser")
end
```
