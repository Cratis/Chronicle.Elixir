```elixir
defmodule MyApp.ReadModels.ReducersGettingStartedOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct order_id: "", total_amount: 0, item_count: 0, last_updated: ""
end
```
