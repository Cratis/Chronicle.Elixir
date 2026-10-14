```elixir title="Parent key from event content"
defmodule MyApp.Events.GroupCreatedWithEventParentKey do
  use Chronicle.Events.EventType, id: "group-created-with-event-parent-key"

  defstruct [:name]
end

defmodule MyApp.Events.UserAddedWithEventParentKey do
  use Chronicle.Events.EventType, id: "user-added-with-event-parent-key"

  defstruct [:group_id, :user_id, :role]
end

defmodule MyApp.ReadModels.GroupMemberWithEventParentKey do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupWithEventParentKey do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMemberWithEventParentKey}]

  defstruct name: nil, members: []
end

defmodule MyApp.Projections.GroupWithEventParentKeyProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupWithEventParentKey

  alias MyApp.Events.{GroupCreatedWithEventParentKey, UserAddedWithEventParentKey}

  from GroupCreatedWithEventParentKey

  children :members, identified_by: :user_id do
    from UserAddedWithEventParentKey,
      parent_key: :group_id,
      key: :user_id,
      set: [user_id: :user_id, role: :role]
  end
end
```
