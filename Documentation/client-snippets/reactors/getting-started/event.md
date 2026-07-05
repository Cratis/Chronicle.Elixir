```elixir
defmodule MyApp.Events.ReactorOrderPlaced do
  use Chronicle.Events.EventType, id: "reactor-order-placed-v1"

  defstruct [:customer_email, :total_amount]
end
```
