```elixir title="Multiple child collections"
defmodule MyApp.Events.GroupCreatedWithMultipleCollections do
  use Chronicle.Events.EventType, id: "group-created-with-multiple-collections"

  defstruct [:name]
end

defmodule MyApp.Events.MemberAddedToGroup do
  use Chronicle.Events.EventType, id: "member-added-to-group"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.TaskAssignedToGroup do
  use Chronicle.Events.EventType, id: "task-assigned-to-group"

  defstruct [:task_id, :title]
end

defmodule MyApp.ReadModels.GroupMemberInMultipleCollections do
  defstruct user_id: nil, role: nil
end

defmodule MyApp.ReadModels.GroupTaskInMultipleCollections do
  defstruct task_id: nil, title: nil
end

defmodule MyApp.ReadModels.GroupWithMultipleCollections do
  use Chronicle.ReadModels.ReadModel,
    types: [
      members: {:list, MyApp.ReadModels.GroupMemberInMultipleCollections},
      tasks: {:list, MyApp.ReadModels.GroupTaskInMultipleCollections}
    ]

  defstruct name: nil, members: [], tasks: []
end

defmodule MyApp.Projections.GroupWithMultipleCollectionsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.GroupWithMultipleCollections

  alias MyApp.Events.{GroupCreatedWithMultipleCollections, MemberAddedToGroup, TaskAssignedToGroup}

  from GroupCreatedWithMultipleCollections

  children :members, identified_by: :user_id do
    from MemberAddedToGroup, key: :user_id, set: [user_id: :user_id, role: :role]
  end

  children :tasks, identified_by: :task_id do
    from TaskAssignedToGroup, key: :task_id, set: [task_id: :task_id, title: :title]
  end
end
```
