```elixir
defmodule MyApp.ModelingEventsOrderId do
  defstruct [:value]
end

defmodule MyApp.ModelingEventsMoney do
  defstruct [:amount, :currency]
end

# Nullable smell — "sometimes there's a discount, sometimes not"
defmodule MyApp.Events.ModelingEventsOrderPlacedWithNullableDiscount do
  use Chronicle.Events.EventType, id: "modeling-events-order-placed-with-nullable-discount"

  defstruct [:id, :total, :discount]
end

# Two facts
defmodule MyApp.Events.ModelingEventsOrderPlaced do
  use Chronicle.Events.EventType, id: "modeling-events-order-placed"

  defstruct [:id, :total]
end

defmodule MyApp.Events.ModelingEventsDiscountApplied do
  use Chronicle.Events.EventType, id: "modeling-events-discount-applied"

  defstruct [:id, :amount]
end
```
