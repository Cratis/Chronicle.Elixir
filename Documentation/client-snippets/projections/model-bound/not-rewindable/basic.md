```elixir
defmodule MyApp.Events.MbNotRewindableAuditEvent do
  use Cratis.Chronicle.Events.EventType, id: "mb-not-rewindable-audit-event"

  defstruct message: "", occurred_at: ""
end

defmodule MyApp.ReadModels.MbNotRewindableAuditLog do
  use Cratis.Chronicle.ReadModels.ReadModel, not_rewindable: true

  defstruct id: "", message: "", timestamp: ""

  from MyApp.Events.MbNotRewindableAuditEvent,
    set: [id: :event_source_id, message: :message, timestamp: :occurred_at]
end
```
