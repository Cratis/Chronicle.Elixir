```elixir
defmodule MyApp.ReadModels.PassiveReducersCustomerBehaviorAnalysis do
  use Chronicle.ReadModels.ReadModel, passive: true

  defstruct unique_customers: 0, average_order_value: 0.0, orders_by_hour: %{}
end
```
