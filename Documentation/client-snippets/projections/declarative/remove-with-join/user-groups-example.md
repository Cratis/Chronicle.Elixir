```elixir
defmodule MyApp.Events.DecRwjUserRegistered do
  use Chronicle.Events.EventType, id: "dec-rwj-user-registered"

  defstruct [:username, :email]
end

defmodule MyApp.Events.DecRwjUserJoinedGroup do
  use Chronicle.Events.EventType, id: "dec-rwj-user-joined-group"

  defstruct [:user_id, :group_id, :role]
end

defmodule MyApp.Events.DecRwjUserLeftGroup do
  use Chronicle.Events.EventType, id: "dec-rwj-user-left-group"

  defstruct [:user_id, :group_id]
end

defmodule MyApp.Events.DecRwjGroupCreated do
  use Chronicle.Events.EventType, id: "dec-rwj-group-created"

  defstruct [:group_name, :group_type]
end

defmodule MyApp.Events.DecRwjGroupDisbanded do
  use Chronicle.Events.EventType, id: "dec-rwj-group-disbanded"

  defstruct []
end

defmodule MyApp.ReadModels.DecRwjUserGroupMembership do
  defstruct group_id: nil, group_name: nil, group_type: nil, joined_at: nil, role: nil
end

defmodule MyApp.ReadModels.DecRwjUserProfile do
  use Chronicle.ReadModels.ReadModel,
    types: [memberships: {:list, MyApp.ReadModels.DecRwjUserGroupMembership}]

  defstruct user_id: nil, username: nil, email: nil, registered_at: nil, memberships: []
end

defmodule MyApp.Projections.DecRwjGroupMembershipProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecRwjUserProfile

  alias MyApp.Events.{
    DecRwjGroupCreated,
    DecRwjGroupDisbanded,
    DecRwjUserJoinedGroup,
    DecRwjUserLeftGroup,
    DecRwjUserRegistered
  }

  from DecRwjUserRegistered, set: [user_id: :event_source_id, registered_at: :occurred]

  children :memberships, identified_by: :group_id do
    from DecRwjUserJoinedGroup,
      parent_key: :user_id,
      key: :group_id,
      set: [group_id: :group_id, role: :role, joined_at: :occurred]

    join DecRwjGroupCreated, set: [group_name: :group_name, group_type: :group_type]

    removed_with DecRwjUserLeftGroup, parent_key: :user_id, key: :group_id

    # The group's own event source id identifies every membership entry to remove.
    removed_with_join DecRwjGroupDisbanded
  end
end
```
