```elixir
defmodule MyApp.Events.MbChildrenOrderCreated do
  use Chronicle.Events.EventType, id: "mb-children-order-created"

  defstruct [:customer_name]
end

defmodule MyApp.Events.MbChildrenLineItemAddedFullExample do
  use Chronicle.Events.EventType, id: "mb-children-line-item-added-full-example"

  defstruct [:order_line_id, :product_name, :quantity]
end

defmodule MyApp.Events.MbChildrenQuantityAdjusted do
  use Chronicle.Events.EventType, id: "mb-children-quantity-adjusted"

  defstruct [:order_line_id, :quantity]
end

defmodule MyApp.Events.MbChildrenLineItemRemovedFullExample do
  use Chronicle.Events.EventType, id: "mb-children-line-item-removed-full-example"

  defstruct [:order_line_id]
end

defmodule MyApp.ReadModels.MbChildrenOrderLine do
  defstruct order_line_id: nil, product_name: nil, quantity: 0
end

defmodule MyApp.ReadModels.MbChildrenFullOrder do
  use Chronicle.ReadModels.ReadModel,
    types: [lines: {:list, MyApp.ReadModels.MbChildrenOrderLine}]

  defstruct order_id: nil, customer_name: nil, lines: []

  from MyApp.Events.MbChildrenOrderCreated,
    set: [order_id: :event_source_id, customer_name: :customer_name]

  children :lines, identified_by: :order_line_id do
    from MyApp.Events.MbChildrenLineItemAddedFullExample,
      key: :order_line_id,
      set: [order_line_id: :order_line_id, product_name: :product_name, quantity: :quantity]

    from MyApp.Events.MbChildrenQuantityAdjusted,
      key: :order_line_id,
      set: [quantity: :quantity]

    removed_with MyApp.Events.MbChildrenLineItemRemovedFullExample, key: :order_line_id
  end
end
```
