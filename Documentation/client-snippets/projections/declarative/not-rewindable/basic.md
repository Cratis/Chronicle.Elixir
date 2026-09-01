```elixir
defmodule MyApp.Events.NotRewindableUserAction do
  use Chronicle.Events.EventType, id: "not-rewindable-user-action"

  defstruct [:action]
end

defmodule MyApp.ReadModels.NotRewindableAuditLogEntry do
  use Chronicle.ReadModels.ReadModel, not_rewindable: true

  defstruct id: nil, action: nil, processed_at: nil, occurred_at: nil

  from_every(set: [processed_at: :occurred])

  from MyApp.Events.NotRewindableUserAction,
    set: [id: :event_source_id, action: :action, occurred_at: :occurred]
end
```
