```elixir title="Map event source id with FromAll"
defmodule MyApp.Events.AccountOpenedDeclarativeAll do
  use Chronicle.Events.EventType, id: "account-opened-declarative-all-v1"

  defstruct [:owner_name]
end

defmodule MyApp.ReadModels.AccountSummaryDeclarativeAll do
  use Chronicle.ReadModels.ReadModel

  defstruct [:account_id, :owner_name]
end

defmodule MyApp.Projections.AccountSummaryDeclarativeAllProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AccountSummaryDeclarativeAll

  alias MyApp.Events.AccountOpenedDeclarativeAll

  from AccountOpenedDeclarativeAll

  from_every set: [account_id: :event_source_id]
end
```
