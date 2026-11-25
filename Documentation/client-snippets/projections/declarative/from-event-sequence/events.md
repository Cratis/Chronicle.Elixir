```elixir
defmodule MyApp.Events.DecFromEventSequenceOrderCreated do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-order-created"

  defstruct [:order_number, :customer_id, :total_amount]
end

defmodule MyApp.Events.DecFromEventSequenceOrderUpdated do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-order-updated"

  defstruct [:order_number, :new_total_amount]
end

defmodule MyApp.Events.DecFromEventSequenceOrderShipped do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-order-shipped"

  defstruct [:order_number, :shipped_at]
end
```
