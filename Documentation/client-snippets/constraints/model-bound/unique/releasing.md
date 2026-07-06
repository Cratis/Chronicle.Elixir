```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueUserRemoved do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueEmail")
end
```
