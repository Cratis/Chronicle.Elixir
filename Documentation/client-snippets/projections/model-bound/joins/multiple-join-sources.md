```elixir
defmodule MyApp.Events.MbJoinsSourcesLineItemAdded do
  use Chronicle.Events.EventType, id: "mb-joins-sources-line-item-added"

  defstruct [:product_id]
end

defmodule MyApp.Events.MbJoinsSourcesProductCatalogUpdated do
  use Chronicle.Events.EventType, id: "mb-joins-sources-product-catalog-updated"

  defstruct [:name, :description]
end

defmodule MyApp.Events.MbJoinsSourcesPricingUpdated do
  use Chronicle.Events.EventType, id: "mb-joins-sources-pricing-updated"

  defstruct [:current_price]
end

defmodule MyApp.ReadModels.MbJoinsSourcesOrderLine do
  defstruct product_id: nil, product_name: nil, description: nil, unit_price: 0
end

defmodule MyApp.ReadModels.MbJoinsSourcesOrder do
  use Chronicle.ReadModels.ReadModel,
    types: [lines: {:list, MyApp.ReadModels.MbJoinsSourcesOrderLine}]

  defstruct order_id: nil, lines: []

  # The lines are keyed by product id, so both joins below resolve implicitly through the
  # child's own key.
  children :lines, identified_by: :product_id do
    from MyApp.Events.MbJoinsSourcesLineItemAdded,
      key: :product_id,
      set: [product_id: :product_id]

    join MyApp.Events.MbJoinsSourcesProductCatalogUpdated,
      set: [product_name: :name, description: :description]

    join MyApp.Events.MbJoinsSourcesPricingUpdated, set: [unit_price: :current_price]
  end
end
```
