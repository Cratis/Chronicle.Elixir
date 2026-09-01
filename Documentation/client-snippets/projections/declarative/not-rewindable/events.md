```elixir
defmodule MyApp.Events.DecNotRewindableUserAction do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-user-action"

  defstruct [:user_id, :action_type, :details]
end

defmodule MyApp.Events.DecNotRewindableSystemEvent do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-system-event"

  defstruct [:component_name, :event_type, :data]
end
```
