```elixir title="Track audit metadata from every event"
defmodule MyApp.Events.AuditableInventoryChangedForEvery do
  use Chronicle.Events.EventType, id: "auditable-inventory-changed-for-every-v1"

  defstruct [:reason]
end

defmodule MyApp.ReadModels.AuditableInventoryStatusFromEvery do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.AuditableInventoryChangedForEvery

  defstruct [:id, :last_modified, :last_event_sequence, :last_correlation_id]

  from AuditableInventoryChangedForEvery,
    set: [id: :event_source_id]

  from_every set: [
    last_modified: :occurred,
    last_event_sequence: "$context.sequenceNumber",
    last_correlation_id: "$context.correlationId"
  ]
end
```
