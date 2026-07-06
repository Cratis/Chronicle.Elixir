```elixir title="AutoMap combined with context mapping"
defmodule MyApp.Events.DecEventContextUserAction do
  use Chronicle.Events.EventType, id: "dec-event-context-user-action"

  defstruct [:user_id, :action_type]
end

defmodule MyApp.Projections.DecEventContextAuditTrailProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecEventContextAuditEntry

  alias MyApp.Events.DecEventContextUserAction

  from DecEventContextUserAction,
    set: [
      event_id: "$context.sequenceNumber",
      occurred_at: :occurred,
      correlation_id: "$context.correlationId"
    ]
end
```
