```elixir title="Events"
defmodule MyApp.Events.DecRwjUserAddedToGroup do
  use Chronicle.Events.EventType, id: "dec-rwj-user-added-to-group"

  defstruct [:group_id]
end

defmodule MyApp.Events.DecRwjGroupDeleted do
  use Chronicle.Events.EventType, id: "dec-rwj-group-deleted"

  defstruct []
end

defmodule MyApp.Events.DecRwjGroupDeletedWithKey do
  use Chronicle.Events.EventType, id: "dec-rwj-group-deleted-with-key"

  defstruct [:deleted_group_id]
end
```
