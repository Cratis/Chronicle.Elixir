```elixir title="Composite key in a child collection"
defmodule MyApp.Events.CompositeOrderCreatedForItems do
  use Chronicle.Events.EventType, id: "composite-order-created-for-items"

  defstruct [:customer_id, :order_number]
end

defmodule MyApp.Events.CompositeItemAddedToOrder do
  use Chronicle.Events.EventType, id: "composite-item-added-to-order"

  defstruct [:customer_id, :order_number, :product_id, :variant, quantity: 0]
end

defmodule MyApp.ReadModels.CompositeItemKey do
  defstruct [:product_id, :variant]
end

defmodule MyApp.ReadModels.CompositeOrderItem do
  defstruct [:id, :product_id, :variant, quantity: 0]
end

defmodule MyApp.ReadModels.CompositeOrderWithItems do
  use Chronicle.ReadModels.ReadModel,
    types: [order_items: {:list, MyApp.ReadModels.CompositeOrderItem}]

  defstruct id: nil, order_items: []
end

defmodule MyApp.Projections.CompositeOrderItemsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.CompositeOrderWithItems

  alias MyApp.Events.{CompositeItemAddedToOrder, CompositeOrderCreatedForItems}

  from CompositeOrderCreatedForItems,
    key: {:composite, [customer_id: :customer_id, order_number: :order_number]}

  children :order_items, identified_by: :id do
    from CompositeItemAddedToOrder,
      parent_key: {:composite, [customer_id: :customer_id, order_number: :order_number]},
      key: {:composite, [product_id: :product_id, variant: :variant]},
      set: [product_id: :product_id, variant: :variant, quantity: :quantity]
  end
end
```
