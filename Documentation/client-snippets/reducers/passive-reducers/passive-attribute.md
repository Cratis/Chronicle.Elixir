```elixir
defmodule PassiveReducersTransactionCompleted do
  use Chronicle.Events.EventType, id: "passive-reducers-transaction-completed"

  defstruct [:amount]
end

defmodule PassiveReducersAdHocReport do
  use Chronicle.ReadModels.ReadModel

  defstruct total_revenue: 0, transaction_count: 0, generated_at: nil
end

# active: false makes the reducer passive: the read model is computed on demand
# instead of being kept up to date in the background.
defmodule PassiveReducersAdHocReportReducer do
  use Chronicle.Reducers.Reducer, model: PassiveReducersAdHocReport, active: false

  @handles PassiveReducersTransactionCompleted

  @impl true
  def reduce(%PassiveReducersTransactionCompleted{} = event, model, context) do
    revenue = if model, do: model.total_revenue, else: 0
    count = if model, do: model.transaction_count, else: 0

    struct!(PassiveReducersAdHocReport,
      total_revenue: revenue + event.amount,
      transaction_count: count + 1,
      generated_at: Map.get(context, :occurred)
    )
  end
end
```
