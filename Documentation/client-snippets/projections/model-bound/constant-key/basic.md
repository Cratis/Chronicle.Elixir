```elixir
defmodule MyApp.Events.ConstantKeyOrderPlaced do
  use Chronicle.Events.EventType, id: "constant-key-order-placed-v1"

  defstruct [:customer_name, :placed_at]
end

defmodule MyApp.ReadModels.GlobalOrderSummary do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ConstantKeyOrderPlaced

  defstruct [:last_customer, :last_order_date]

  # A literal `$value(...)` key expression routes every event to the same
  # instance, regardless of which event source produced it.
  from ConstantKeyOrderPlaced,
    key: "$value(global)",
    set: [last_customer: :customer_name, last_order_date: :placed_at]
end
```
