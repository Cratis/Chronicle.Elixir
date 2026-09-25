```elixir
defmodule MyApp.Events.ReducersEventSequenceLogOrderPlaced do
  use Chronicle.Events.EventType, id: "reducers-event-sequence-log-order-placed"

  defstruct order_id: ""
end

defmodule MyApp.ReadModels.ReducersEventSequenceLocalOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct order_count: 0, last_order_at: nil
end

defmodule MyApp.Reducers.ReducersEventSequenceLocalOrderSummaryReducer do
  # Reducers observe the event log by default.
  use Chronicle.Reducers.Reducer,
    model: MyApp.ReadModels.ReducersEventSequenceLocalOrderSummary

  alias MyApp.Events.ReducersEventSequenceLogOrderPlaced
  alias MyApp.ReadModels.ReducersEventSequenceLocalOrderSummary

  @handles ReducersEventSequenceLogOrderPlaced

  @impl true
  def reduce(%ReducersEventSequenceLogOrderPlaced{}, current, context) do
    count = if current, do: current.order_count, else: 0

    %ReducersEventSequenceLocalOrderSummary{
      order_count: count + 1,
      last_order_at: Map.get(context, :occurred)
    }
  end
end
```
