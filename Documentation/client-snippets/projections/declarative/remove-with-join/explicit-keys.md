```elixir
defmodule MyApp.Projections.DecRwjUserWithGroupsExplicitKeyProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecRwjUserWithGroupsExplicitKey

  alias MyApp.Events.{DecRwjUserAddedToGroup, DecRwjGroupDeletedWithKey}

  children :groups, identified_by: :group_id do
    from DecRwjUserAddedToGroup, set: [group_id: :group_id]

    # key: names the event property that identifies which membership to remove, for when it
    # is not the removing event's own event source id.
    removed_with_join DecRwjGroupDeletedWithKey, key: :deleted_group_id
  end
end
```
