```elixir title="Remove children"
defmodule MyApp.Events.GroupCreatedWithRemoval do
  use Chronicle.Events.EventType, id: "group-created-with-removal"

  defstruct [:name]
end

defmodule MyApp.Events.UserAddedWithRemoval do
  use Chronicle.Events.EventType, id: "user-added-with-removal"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.UserRemovedWithRemoval do
  use Chronicle.Events.EventType, id: "user-removed-with-removal"

  defstruct [:user_id]
end

defmodule MyApp.ReadModels.GroupMemberWithRemoval do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupWithRemoval do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMemberWithRemoval}]

  defstruct name: nil, members: []
end

defmodule MyApp.Projections.GroupWithRemovalProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupWithRemoval

  alias MyApp.Events.{GroupCreatedWithRemoval, UserAddedWithRemoval, UserRemovedWithRemoval}

  from GroupCreatedWithRemoval

  children :members, identified_by: :user_id do
    from UserAddedWithRemoval, key: :user_id, set: [user_id: :user_id, role: :role]
    removed_with UserRemovedWithRemoval, key: :user_id
  end
end
```
