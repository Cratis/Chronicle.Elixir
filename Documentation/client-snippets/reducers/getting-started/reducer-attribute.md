```elixir
defmodule MyApp.ReadModels.ReducersGettingStartedAttributeOrderSummary do
  defstruct order_id: ""
end

defmodule MyApp.Reducers.ReducersGettingStartedAttributeOrderSummaryReducer do
  use Cratis.Chronicle.Reducers.Reducer,
    model: MyApp.ReadModels.ReducersGettingStartedAttributeOrderSummary,
    id: "order-summary"

  @impl true
  def reduce(_event, model, _context), do: model
end
```
