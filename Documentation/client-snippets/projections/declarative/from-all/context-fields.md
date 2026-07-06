```elixir title="Map context fields with FromAll"
defmodule MyApp.Events.AccountTouchedDeclarativeAll do
  use Chronicle.Events.EventType, id: "account-touched-declarative-all-v1"

  defstruct [:reason]
end

defmodule MyApp.ReadModels.AccountAuditDeclarativeAll do
  use Chronicle.ReadModels.ReadModel

  defstruct [:last_updated, :last_event_sequence, :last_correlation_id]
end

defmodule MyApp.Projections.AccountAuditDeclarativeAllProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AccountAuditDeclarativeAll

  alias MyApp.Events.AccountTouchedDeclarativeAll

  from AccountTouchedDeclarativeAll

  from_every set: [
    last_updated: :occurred,
    last_event_sequence: "$context.sequenceNumber",
    last_correlation_id: "$context.correlationId"
  ]
end
```
