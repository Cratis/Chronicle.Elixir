```elixir title="Map multiple context fields"
defmodule MyApp.Events.AccountTouchedDeclarativeEvery do
  use Chronicle.Events.EventType, id: "account-touched-declarative-every-v1"

  defstruct [:reason]
end

defmodule MyApp.ReadModels.AccountAuditDeclarativeEvery do
  use Chronicle.ReadModels.ReadModel

  defstruct [:last_updated, :last_event_sequence, :last_correlation_id]
end

defmodule MyApp.Projections.AccountAuditDeclarativeEveryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AccountAuditDeclarativeEvery

  alias MyApp.Events.AccountTouchedDeclarativeEvery

  from AccountTouchedDeclarativeEvery

  from_every set: [
    last_updated: :occurred,
    last_event_sequence: "$context.sequenceNumber",
    last_correlation_id: "$context.correlationId"
  ]
end
```
