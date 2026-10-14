```elixir
defmodule MyApp.Projections.DecRwjUserWithGroupsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecRwjUserWithGroups

  alias MyApp.Events.{DecRwjUserAddedToGroup, DecRwjGroupDeleted}

  children :groups, identified_by: :group_id do
    from DecRwjUserAddedToGroup, set: [group_id: :group_id]

    # removed_with_join defaults its key to the event source id, so GroupDeleted's own event
    # source id (the group's id) is matched against every user's membership entry with the
    # same group_id — the event never has to come from this user's own event stream.
    removed_with_join DecRwjGroupDeleted
  end
end
```
