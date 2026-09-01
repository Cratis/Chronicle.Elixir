```elixir title="Read model with composite key"
defmodule MyApp.ReadModels.CompositeOrder do
  defstruct [:id, :customer_name, :order_date, :shipped_date]
end
```
