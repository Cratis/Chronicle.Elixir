```elixir title="Events"
defmodule MyApp.Events.DecEventContextUserLoggedIn do
  use Chronicle.Events.EventType, id: "dec-event-context-user-logged-in"

  defstruct [:username]
end

defmodule MyApp.Events.DecEventContextUserPerformedAction do
  use Chronicle.Events.EventType, id: "dec-event-context-user-performed-action"

  defstruct [:user_id, :action_type]
end
```
