```elixir
defmodule MyApp.ReducersGettingStartedOrderService do
  alias MyApp.ReadModels.ReducersGettingStartedOrderSummary

  def get_order_summary(order_id) do
    Chronicle.read_model(ReducersGettingStartedOrderSummary, order_id)
  end
end
```
