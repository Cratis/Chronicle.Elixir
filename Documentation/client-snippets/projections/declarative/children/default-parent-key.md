```elixir title="Default parent key"
defmodule MyApp.Events.GroupCreatedWithDefaultParentKey do
  use Chronicle.Events.EventType, id: "group-created-with-default-parent-key"

  defstruct [:name]
end

defmodule MyApp.Events.UserAddedWithDefaultParentKey do
  use Chronicle.Events.EventType, id: "user-added-with-default-parent-key"

  defstruct [:user_id, :role]
end

defmodule MyApp.ReadModels.GroupMemberWithDefaultParentKey do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupWithDefaultParentKey do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMemberWithDefaultParentKey}]

  defstruct name: nil, members: []
end

defmodule MyApp.Projections.GroupWithDefaultParentKeyProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupWithDefaultParentKey

  alias MyApp.Events.{GroupCreatedWithDefaultParentKey, UserAddedWithDefaultParentKey}

  from GroupCreatedWithDefaultParentKey

  # parent_key is not given, so the event source id of UserAddedWithDefaultParentKey
  # identifies the group the member belongs to.
  children :members, identified_by: :user_id do
    from UserAddedWithDefaultParentKey,
      key: :user_id,
      set: [user_id: :user_id, role: :role]
  end
end
```
