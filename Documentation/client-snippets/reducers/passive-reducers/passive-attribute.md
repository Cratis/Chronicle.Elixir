```elixir
defmodule MyApp.Events.PassiveReducersTransactionCompleted do
  use Chronicle.Events.EventType, id: "passive-reducers-transaction-completed"

  defstruct amount: 0.0
end

defmodule MyApp.ReadModels.PassiveReducersAdHocReport do
  use Chronicle.ReadModels.ReadModel, passive: true

  defstruct total_revenue: 0.0, transaction_count: 0, generated_at: nil
end

defmodule MyApp.Reducers.PassiveReducersAdHocReportReducer do
  use Chronicle.Reducers.Reducer,
    model: MyApp.ReadModels.PassiveReducersAdHocReport,
    active: false

  alias MyApp.Events.PassiveReducersTransactionCompleted
  alias MyApp.ReadModels.PassiveReducersAdHocReport

  @handles PassiveReducersTransactionCompleted

  @impl true
  def reduce(%PassiveReducersTransactionCompleted{} = event, current, context) do
    revenue = if current, do: current.total_revenue, else: 0.0
    count = if current, do: current.transaction_count, else: 0

    %PassiveReducersAdHocReport{
      total_revenue: revenue + event.amount,
      transaction_count: count + 1,
      generated_at: Map.get(context, :occurred)
    }
  end
end
```
