```elixir
defmodule MyApp.Events.MbChildrenGroupMemberAdded do
  use Chronicle.Events.EventType, id: "mb-children-group-member-added"

  defstruct [:member_id, :member_name]
end

defmodule MyApp.Events.MbChildrenMemberDeletedElsewhere do
  use Chronicle.Events.EventType, id: "mb-children-member-deleted-elsewhere"

  defstruct [:member_id]
end

defmodule MyApp.ReadModels.MbChildrenGroupMember do
  defstruct member_id: nil, member_name: nil
end

defmodule MyApp.ReadModels.MbChildrenGroupWithJoinRemoval do
  use Chronicle.ReadModels.ReadModel,
    types: [members: {:list, MyApp.ReadModels.MbChildrenGroupMember}]

  defstruct group_id: nil, members: []

  children :members, identified_by: :member_id do
    from MyApp.Events.MbChildrenGroupMemberAdded,
      key: :member_id,
      set: [member_id: :member_id, member_name: :member_name]

    # removed_with_join matches by a property on an event from a different stream, rather than
    # by the child's own key — the event never has to come from the group's own event source.
    removed_with_join MyApp.Events.MbChildrenMemberDeletedElsewhere, key: :member_id
  end
end
```
