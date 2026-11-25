```elixir
defmodule MyApp.Events.MbChildrenItemAddedToCart do
  use Cratis.Chronicle.Events.EventType, id: "mb-children-item-added-to-cart"

  defstruct [:cart_item_id, :product_name, :quantity]
end

defmodule MyApp.Events.MbChildrenQuantityIncreased do
  use Cratis.Chronicle.Events.EventType, id: "mb-children-quantity-increased"

  defstruct [:cart_item_id, :amount]
end

defmodule MyApp.ReadModels.MbChildrenCartItem do
  defstruct cart_item_id: nil, product_name: nil, quantity: 0
end

defmodule MyApp.ReadModels.MbChildrenCart do
  use Cratis.Chronicle.ReadModels.ReadModel, types: [items: {:list, MyApp.ReadModels.MbChildrenCartItem}]

  defstruct cart_id: nil, items: []

  children :items, identified_by: :cart_item_id do
    from MyApp.Events.MbChildrenItemAddedToCart,
      key: :cart_item_id,
      set: [
        cart_item_id: :cart_item_id,
        product_name: :product_name,
        quantity: :quantity
      ]

    from MyApp.Events.MbChildrenQuantityIncreased,
      key: :cart_item_id,
      add: [quantity: :amount]
  end
end
```
