```elixir title="Events used by composite key projections"
defmodule MyApp.Events.CompositeOrderCreated do
  use Chronicle.Events.EventType, id: "composite-order-created"

  defstruct [:customer_id, :order_number, :customer_name, :order_date]
end

defmodule MyApp.Events.CompositeOrderShipped do
  use Chronicle.Events.EventType, id: "composite-order-shipped"

  defstruct [:customer_id, :order_number, :shipped_date]
end

defmodule MyApp.Events.CompositeUserAction do
  use Chronicle.Events.EventType, id: "composite-user-action"

  defstruct [:user_id, :action, :details]
end
```
