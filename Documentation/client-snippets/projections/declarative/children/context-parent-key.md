```elixir title="Explicit parent key from context"
defmodule MyApp.Events.GroupCreatedWithContextParentKey do
  use Chronicle.Events.EventType, id: "group-created-with-context-parent-key"

  defstruct [:name]
end

defmodule MyApp.Events.UserAddedWithContextParentKey do
  use Chronicle.Events.EventType, id: "user-added-with-context-parent-key"

  defstruct [:user_id, :role]
end

defmodule MyApp.ReadModels.GroupMemberWithContextParentKey do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupWithContextParentKey do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.GroupMemberWithContextParentKey}]

  defstruct name: nil, members: []
end

defmodule MyApp.Projections.GroupWithContextParentKeyProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupWithContextParentKey

  alias MyApp.Events.{GroupCreatedWithContextParentKey, UserAddedWithContextParentKey}

  from GroupCreatedWithContextParentKey

  children :members, identified_by: :user_id do
    from UserAddedWithContextParentKey,
      parent_key: :event_source_id,
      key: :user_id,
      set: [user_id: :user_id, role: :role]
  end
end
```
