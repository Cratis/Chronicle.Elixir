```elixir title="Projection with children"
defmodule MyApp.Events.GroupCreatedForChildren do
  use Chronicle.Events.EventType, id: "group-created-for-children"

  defstruct [:name, :description]
end

defmodule MyApp.Events.UserAddedToGroupForChildren do
  use Chronicle.Events.EventType, id: "user-added-to-group-for-children"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.UserRoleChangedForChildren do
  use Chronicle.Events.EventType, id: "user-role-changed-for-children"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.UserRemovedFromGroupForChildren do
  use Chronicle.Events.EventType, id: "user-removed-from-group-for-children"

  defstruct [:user_id]
end

defmodule MyApp.ReadModels.GroupMemberForChildren do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupForChildren do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMemberForChildren}]

  defstruct name: nil, description: nil, members: []
end

defmodule MyApp.Projections.GroupProjectionForChildren do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupForChildren

  alias MyApp.Events.{
    GroupCreatedForChildren,
    UserAddedToGroupForChildren,
    UserRemovedFromGroupForChildren,
    UserRoleChangedForChildren
  }

  from GroupCreatedForChildren

  children :members, identified_by: :user_id do
    from UserAddedToGroupForChildren,
      key: :user_id,
      set: [user_id: :user_id, role: :role]

    from UserRoleChangedForChildren,
      key: :user_id,
      set: [role: :role]

    removed_with UserRemovedFromGroupForChildren, key: :user_id
  end
end
```
