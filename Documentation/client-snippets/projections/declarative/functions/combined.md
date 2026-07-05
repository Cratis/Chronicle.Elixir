```elixir title="Combined functions"
defmodule MyApp.Events.DecFunctionsTransaction do
  use Chronicle.Events.EventType, id: "dec-functions-transaction"

  defstruct [:amount]
end

defmodule MyApp.ReadModels.DecFunctionsTransactionSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct transaction_count: 0, total_amount: 0, processed_events: 0
end

defmodule MyApp.Projections.DecFunctionsTransactionSummaryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecFunctionsTransactionSummary

  alias MyApp.Events.DecFunctionsTransaction

  from DecFunctionsTransaction,
    count: :transaction_count,
    add: [total_amount: :amount, processed_events: 1]
end
```
