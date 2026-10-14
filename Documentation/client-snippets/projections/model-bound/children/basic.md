```elixir
defmodule MyApp.Events.MbChildrenLineItemAdded do
  use Chronicle.Events.EventType, id: "mb-children-line-item-added"

  defstruct [:line_item_id, :product_name, :quantity]
end

defmodule MyApp.ReadModels.MbChildrenLineItem do
  defstruct line_item_id: nil, product_name: nil, quantity: 0
end

defmodule MyApp.ReadModels.MbChildrenOrder do
  use Chronicle.ReadModels.ReadModel, types: [lines: {:list, MyApp.ReadModels.MbChildrenLineItem}]

  defstruct order_id: nil, lines: []

  children :lines,
    from: MyApp.Events.MbChildrenLineItemAdded,
    identified_by: :line_item_id,
    key: :line_item_id,
    set: [
      line_item_id: :line_item_id,
      product_name: :product_name,
      quantity: :quantity
    ]
end
```
