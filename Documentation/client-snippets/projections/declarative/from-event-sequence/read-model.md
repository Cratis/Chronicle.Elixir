```elixir
defmodule MyApp.ReadModels.DecFromEventSequenceOrder do
  # status is one of :created, :processing, :shipped, :delivered, :canceled
  defstruct [
    :order_number,
    :customer_id,
    :total_amount,
    :status,
    :created_at,
    :shipped_at
  ]
end
```
