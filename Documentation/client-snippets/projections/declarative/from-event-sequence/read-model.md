```elixir
defmodule MyApp.ReadModels.DecFromEventSequenceOrder do
  use Chronicle.ReadModels.ReadModel

  # status is one of "Created", "Processing", "Shipped", "Delivered", "Canceled"
  defstruct order_number: "",
            customer_id: "",
            total_amount: 0.0,
            status: "",
            created_at: "",
            shipped_at: ""
end
```
