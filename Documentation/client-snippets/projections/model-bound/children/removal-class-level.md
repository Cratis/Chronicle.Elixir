```elixir
# Elixir has no separate child-type module to carry a class-level removal attribute — a child's
# `removed_with` always lives inside the owning `children` block, so this is the same declaration
# as the property-level form.
defmodule MyApp.Events.MbChildrenLineItemAddedForClassRemoval do
  use Chronicle.Events.EventType, id: "mb-children-line-item-added-for-class-removal"

  defstruct [:line_item_id, :product_name]
end

defmodule MyApp.Events.MbChildrenLineItemRemovedClassLevel do
  use Chronicle.Events.EventType, id: "mb-children-line-item-removed-class-level"

  defstruct [:line_item_id]
end

defmodule MyApp.ReadModels.MbChildrenRemovableLineClassLevel do
  defstruct line_item_id: nil, product_name: nil
end

defmodule MyApp.ReadModels.MbChildrenOrderWithClassLevelRemoval do
  use Chronicle.ReadModels.ReadModel,
    types: [lines: {:list, MyApp.ReadModels.MbChildrenRemovableLineClassLevel}]

  defstruct order_id: nil, lines: []

  children :lines, identified_by: :line_item_id do
    from MyApp.Events.MbChildrenLineItemAddedForClassRemoval,
      key: :line_item_id,
      set: [line_item_id: :line_item_id, product_name: :product_name]

    removed_with MyApp.Events.MbChildrenLineItemRemovedClassLevel, key: :line_item_id
  end
end
```
