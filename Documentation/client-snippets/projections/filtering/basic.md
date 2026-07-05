```elixir
defmodule MyApp.Events.FilteringOrderPlaced do
  use Chronicle.Events.EventType

  defstruct [:customer_id, :total_amount]
end

defmodule MyApp.Events.FilteringOrderShipped do
  use Chronicle.Events.EventType

  defstruct [:shipped_at]
end

defmodule MyApp.ReadModels.FilteringOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct customer_id: nil, total_amount: nil, shipped_at: nil

  from MyApp.Events.FilteringOrderPlaced,
    set: [customer_id: :customer_id, total_amount: :total_amount]

  from MyApp.Events.FilteringOrderShipped,
    set: [shipped_at: :shipped_at]
end
```
