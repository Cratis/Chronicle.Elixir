```elixir
defmodule MyApp.Events.MbNotRewindableAuditEvent do
  use Chronicle.Events.EventType, id: "mb-not-rewindable-audit-event"

  defstruct message: "", occurred_at: ""
end

defmodule MyApp.ReadModels.MbNotRewindableAuditLog do
  use Chronicle.ReadModels.ReadModel, not_rewindable: true

  defstruct id: "", message: "", timestamp: ""

  # occurred_at travels as camelCase JSON.
  from MyApp.Events.MbNotRewindableAuditEvent,
    set: [id: :event_source_id, message: :message, timestamp: "occurredAt"]
end
```
