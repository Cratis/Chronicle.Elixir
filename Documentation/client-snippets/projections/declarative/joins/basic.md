```elixir
defmodule MyApp.Projections.DecJoinsUserProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecJoinsUser

  alias MyApp.Events.{
    DecJoinsUserCreated,
    DecJoinsUserAssignedToGroup,
    DecJoinsGroupCreated,
    DecJoinsGroupRenamed
  }

  from DecJoinsUserCreated

  from DecJoinsUserAssignedToGroup,
    key: :user_id,
    set: [group_id: :event_source_id]

  join DecJoinsGroupCreated, on: :group_id
  join DecJoinsGroupRenamed, on: :group_id
end
```
