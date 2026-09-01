```elixir
defmodule MyApp.Events.UserChangedEveryMultiple do
  use Chronicle.Events.EventType, id: "user-changed-every-multiple"

  defstruct [:name]
end

defmodule MyApp.ReadModels.UserAuditEveryMultiple do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, name: nil, last_updated: nil, subject_id: nil

  from MyApp.Events.UserChangedEveryMultiple,
    set: [name: :name]

  # Every declaration contributes - they are merged, not replaced.
  from_every(set: [last_updated: :occurred])
  from_every(set: [subject_id: :event_source_id])
end
```
