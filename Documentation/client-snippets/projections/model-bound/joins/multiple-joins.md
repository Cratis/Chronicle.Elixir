```elixir
defmodule MyApp.Events.JoinsMultipleOrderPlaced do
  use Chronicle.Events.EventType, id: "joins-multiple-order-placed-v1"

  defstruct [:customer_id]
end

defmodule MyApp.Events.JoinsMultipleCustomerCreated do
  use Chronicle.Events.EventType, id: "joins-multiple-customer-created-v1"

  defstruct [:name]
end

defmodule MyApp.Events.JoinsCustomerUpdated do
  use Chronicle.Events.EventType, id: "joins-customer-updated-v1"

  defstruct [:email]
end

defmodule MyApp.Events.JoinsShippingAddressSet do
  use Chronicle.Events.EventType, id: "joins-shipping-address-set-v1"

  defstruct [:address]
end

defmodule MyApp.ReadModels.JoinsEnrichedOrder do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    JoinsMultipleOrderPlaced,
    JoinsMultipleCustomerCreated,
    JoinsCustomerUpdated,
    JoinsShippingAddressSet
  }

  defstruct [:order_id, :customer_id, :customer_name, :customer_email, :shipping_address]

  from JoinsMultipleOrderPlaced,
    set: [order_id: :event_source_id, customer_id: :customer_id]

  join JoinsMultipleCustomerCreated,
    on: "customer_id",
    set: [customer_name: :name]

  join JoinsCustomerUpdated,
    on: "customer_id",
    set: [customer_email: :email]

  # Raised on the order's own event source, so it joins on the read model's
  # own key rather than a separate correlating property.
  join JoinsShippingAddressSet,
    on: "order_id",
    set: [shipping_address: :address]
end
```
