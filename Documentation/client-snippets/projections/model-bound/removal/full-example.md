```elixir
# Events
defmodule MyApp.Events.MbRemovalFullShoppingCartCreated do
  use Chronicle.Events.EventType, id: "mb-removal-full-shopping-cart-created"

  defstruct [:customer_name]
end

defmodule MyApp.Events.MbRemovalFullItemAddedToCart do
  use Chronicle.Events.EventType, id: "mb-removal-full-item-added-to-cart"

  defstruct [:item_id, :product_name, :price]
end

defmodule MyApp.Events.MbRemovalFullItemRemovedFromCart do
  use Chronicle.Events.EventType, id: "mb-removal-full-item-removed-from-cart"

  defstruct [:cart_id, :item_id]
end

defmodule MyApp.Events.MbRemovalFullCartCheckedOut do
  use Chronicle.Events.EventType, id: "mb-removal-full-cart-checked-out"

  defstruct []
end

defmodule MyApp.Events.MbRemovalFullCartAbandoned do
  use Chronicle.Events.EventType, id: "mb-removal-full-cart-abandoned"

  defstruct []
end

# Read models
defmodule MyApp.ReadModels.MbRemovalFullCartItem do
  defstruct id: nil, product: nil, price: 0
end

defmodule MyApp.ReadModels.MbRemovalFullShoppingCart do
  use Chronicle.ReadModels.ReadModel,
    types: [items: {:list, MyApp.ReadModels.MbRemovalFullCartItem}]

  alias MyApp.Events.{
    MbRemovalFullCartAbandoned,
    MbRemovalFullCartCheckedOut,
    MbRemovalFullItemAddedToCart,
    MbRemovalFullItemRemovedFromCart,
    MbRemovalFullShoppingCartCreated
  }

  defstruct id: nil, customer: nil, items: []

  from MbRemovalFullShoppingCartCreated,
    set: [id: :event_source_id, customer: :customer_name]

  # Either event removes the whole cart.
  removed_with MbRemovalFullCartCheckedOut, []
  removed_with MbRemovalFullCartAbandoned, []

  children :items, identified_by: :id do
    from MbRemovalFullItemAddedToCart,
      key: :item_id,
      set: [id: :item_id, product: :product_name, price: :price]

    # Removes one item; `key` identifies the item and `parent_key` the cart it belongs to.
    removed_with MbRemovalFullItemRemovedFromCart, key: :item_id, parent_key: :cart_id
  end
end
```
