```elixir title="Map the event source id"
defmodule MyApp.Events.AccountOpenedDeclarativeEvery do
  use Chronicle.Events.EventType, id: "account-opened-declarative-every-v1"

  defstruct [:owner_name]
end

defmodule MyApp.ReadModels.AccountSummaryDeclarativeEvery do
  use Chronicle.ReadModels.ReadModel

  defstruct [:account_id, :owner_name]
end

defmodule MyApp.Projections.AccountSummaryDeclarativeEveryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.AccountSummaryDeclarativeEvery

  alias MyApp.Events.AccountOpenedDeclarativeEvery

  from AccountOpenedDeclarativeEvery,
    set: [owner_name: :owner_name]

  from_every set: [account_id: :event_source_id]
end
```
