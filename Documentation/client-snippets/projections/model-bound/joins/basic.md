```elixir
defmodule MyApp.Events.JoinsOrderPlaced do
  use Chronicle.Events.EventType, id: "joins-order-placed-v1"

  defstruct [:customer_id, :amount]
end

defmodule MyApp.Events.JoinsCustomerCreated do
  use Chronicle.Events.EventType, id: "joins-customer-created-v1"

  defstruct [:name]
end

defmodule MyApp.ReadModels.JoinsOrderSummary do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{JoinsOrderPlaced, JoinsCustomerCreated}

  defstruct [:order_id, :amount, :customer_id, :customer_name]

  from JoinsOrderPlaced,
    set: [order_id: :event_source_id, amount: :amount, customer_id: :customer_id]

  join JoinsCustomerCreated,
    on: "customer_id",
    set: [customer_name: :name]
end
```
