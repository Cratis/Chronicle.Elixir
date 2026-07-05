```elixir
defmodule MyApp.Events.CountersOrderPlaced do
  use Chronicle.Events.EventType, id: "counters-order-placed-v1"

  defstruct []
end

defmodule MyApp.Events.CountersOrderCancelled do
  use Chronicle.Events.EventType, id: "counters-order-cancelled-v1"

  defstruct []
end

defmodule MyApp.ReadModels.CountersEventMetrics do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{CountersOrderPlaced, CountersOrderCancelled}

  defstruct [:id, total_orders: 0, cancelled_orders: 0]

  from CountersOrderPlaced,
    set: [id: :event_source_id],
    count: :total_orders

  from CountersOrderCancelled,
    count: :cancelled_orders
end
```
