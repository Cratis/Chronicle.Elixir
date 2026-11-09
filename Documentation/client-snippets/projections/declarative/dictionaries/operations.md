```elixir title="Dictionary operations keyed per event"
defmodule MyApp.Events.DecDictionaryItemSold do
  use Chronicle.Events.EventType, id: "dec-dictionary-item-sold"

  defstruct category: "", quantity: 0
end

defmodule MyApp.Events.DecDictionaryItemReturned do
  use Chronicle.Events.EventType, id: "dec-dictionary-item-returned"

  defstruct category: "", quantity: 0
end

defmodule MyApp.ReadModels.DecDictionarySales do
  use Chronicle.ReadModels.ReadModel

  defstruct units_by_category: %{},
            sales_by_category: %{},
            sales_by_user: %{},
            first_sale_by_category: %{}
end

defmodule MyApp.Projections.DecDictionarySalesProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecDictionarySales

  alias MyApp.Events.{DecDictionaryItemReturned, DecDictionaryItemSold}

  from DecDictionaryItemSold,
    add: [units_by_category: {:entry, {:event_content, :category}, :quantity}],
    increment: [sales_by_category: {:event_content, :category}],
    count: [sales_by_user: {:caused_by, :subject}],
    set_once: [first_sale_by_category: {:entry, {:event_content, :category}, :occurred}]

  from DecDictionaryItemReturned,
    subtract: [units_by_category: {:entry, {:event_content, :category}, :quantity}],
    decrement: [sales_by_category: {:event_content, :category}]
end
```
