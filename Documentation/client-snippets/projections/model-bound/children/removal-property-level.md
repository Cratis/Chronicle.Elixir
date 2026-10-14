```elixir
defmodule MyApp.Events.MbChildrenLineItemAddedForRemoval do
  use Chronicle.Events.EventType, id: "mb-children-line-item-added-for-removal"

  defstruct [:line_item_id, :product_name]
end

defmodule MyApp.Events.MbChildrenLineItemRemoved do
  use Chronicle.Events.EventType, id: "mb-children-line-item-removed"

  defstruct [:line_item_id]
end

defmodule MyApp.ReadModels.MbChildrenRemovableLine do
  defstruct line_item_id: nil, product_name: nil
end

defmodule MyApp.ReadModels.MbChildrenOrderWithRemoval do
  use Chronicle.ReadModels.ReadModel,
    types: [lines: {:list, MyApp.ReadModels.MbChildrenRemovableLine}]

  defstruct order_id: nil, lines: []

  children :lines, identified_by: :line_item_id do
    from MyApp.Events.MbChildrenLineItemAddedForRemoval,
      key: :line_item_id,
      set: [line_item_id: :line_item_id, product_name: :product_name]

    removed_with MyApp.Events.MbChildrenLineItemRemoved, key: :line_item_id
  end
end
```
