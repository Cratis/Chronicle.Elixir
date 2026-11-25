```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueMultiRemoveUserRemoved do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-multi-remove-user-removed"

  defstruct [:user_id]

  remove_constraint("UniqueEmail")
  remove_constraint("UniqueUsername")
end
```
