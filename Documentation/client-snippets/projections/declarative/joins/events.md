```elixir title="Events"
defmodule MyApp.Events.DecJoinsUserCreated do
  use Chronicle.Events.EventType, id: "dec-joins-user-created"

  defstruct [:name, :email]
end

defmodule MyApp.Events.DecJoinsUserAssignedToGroup do
  use Chronicle.Events.EventType, id: "dec-joins-user-assigned-to-group"

  defstruct [:user_id, :group_id]
end

defmodule MyApp.Events.DecJoinsGroupCreated do
  use Chronicle.Events.EventType, id: "dec-joins-group-created"

  defstruct [:name, :description]
end

defmodule MyApp.Events.DecJoinsGroupRenamed do
  use Chronicle.Events.EventType, id: "dec-joins-group-renamed"

  defstruct [:new_name]
end
```
