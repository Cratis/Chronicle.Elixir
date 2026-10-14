```elixir title="Child lifecycle events"
defmodule MyApp.Events.GroupCreatedForChildEvents do
  use Chronicle.Events.EventType, id: "group-created-for-child-events"

  defstruct [:name, :description]
end

defmodule MyApp.Events.UserAddedToGroupForChildEvents do
  use Chronicle.Events.EventType, id: "user-added-to-group-for-child-events"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.UserRoleChangedForChildEvents do
  use Chronicle.Events.EventType, id: "user-role-changed-for-child-events"

  defstruct [:user_id, :role]
end

defmodule MyApp.Events.UserRemovedFromGroupForChildEvents do
  use Chronicle.Events.EventType, id: "user-removed-from-group-for-child-events"

  defstruct [:user_id]
end
```
