```elixir
# Events
defmodule MyApp.Events.MbJoinsFullOrderPlaced do
  use Chronicle.Events.EventType, id: "mb-joins-full-order-placed"

  defstruct [:customer_id, :placed_at]
end

defmodule MyApp.Events.MbJoinsFullCustomerRegistered do
  use Chronicle.Events.EventType, id: "mb-joins-full-customer-registered"

  defstruct [:name, :email]
end

defmodule MyApp.Events.MbJoinsFullCustomerProfileUpdated do
  use Chronicle.Events.EventType, id: "mb-joins-full-customer-profile-updated"

  defstruct [:phone_number]
end

defmodule MyApp.Events.MbJoinsFullLineItemAdded do
  use Chronicle.Events.EventType, id: "mb-joins-full-line-item-added"

  defstruct [:product_id, :quantity]
end

defmodule MyApp.Events.MbJoinsFullProductCreated do
  use Chronicle.Events.EventType, id: "mb-joins-full-product-created"

  defstruct [:name, :price]
end

defmodule MyApp.Events.MbJoinsFullProductPriceChanged do
  use Chronicle.Events.EventType, id: "mb-joins-full-product-price-changed"

  defstruct [:new_price]
end

# Read models
defmodule MyApp.ReadModels.MbJoinsFullLineItemDetails do
  defstruct product_id: nil, quantity: 0, product_name: nil, price: 0
end

defmodule MyApp.ReadModels.MbJoinsFullOrderDetails do
  use Chronicle.ReadModels.ReadModel,
    types: [items: {:list, MyApp.ReadModels.MbJoinsFullLineItemDetails}]

  alias MyApp.Events.{
    MbJoinsFullCustomerProfileUpdated,
    MbJoinsFullCustomerRegistered,
    MbJoinsFullLineItemAdded,
    MbJoinsFullOrderPlaced,
    MbJoinsFullProductCreated,
    MbJoinsFullProductPriceChanged
  }

  defstruct order_id: nil,
            placed_at: nil,
            customer_id: nil,
            customer_name: nil,
            customer_email: nil,
            customer_phone: nil,
            items: []

  from MbJoinsFullOrderPlaced,
    set: [order_id: :event_source_id, placed_at: :placed_at, customer_id: :customer_id]

  # Join customer information
  join MbJoinsFullCustomerRegistered,
    on: "customer_id",
    set: [customer_name: :name, customer_email: :email]

  join MbJoinsFullCustomerProfileUpdated,
    on: "customer_id",
    set: [customer_phone: :phone_number]

  # Keyed by product id, so the joins below resolve implicitly through the child's own key.
  children :items, identified_by: :product_id do
    from MbJoinsFullLineItemAdded,
      key: :product_id,
      set: [product_id: :product_id, quantity: :quantity]

    # Join product information
    join MbJoinsFullProductCreated, set: [product_name: :name, price: :price]
    join MbJoinsFullProductPriceChanged, set: [price: :new_price]
  end
end
```
