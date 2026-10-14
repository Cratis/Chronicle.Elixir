```elixir title="Join with a composite key"
defmodule MyApp.Events.CompositeProductUpdated do
  use Chronicle.Events.EventType, id: "composite-product-updated"

  defstruct [:product_id, :variant, :product_name]
end

defmodule MyApp.ReadModels.CompositeProductKey do
  defstruct [:product_id, :variant]
end

defmodule MyApp.ReadModels.CompositeOrderLine do
  use Chronicle.ReadModels.ReadModel

  defstruct [:product_key, :product_name]
end

defmodule MyApp.Projections.CompositeOrderLineProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.CompositeOrderLine

  alias MyApp.Events.CompositeProductUpdated

  join CompositeProductUpdated,
    on: :product_key,
    key: {:composite, [product_id: :product_id, variant: :variant]},
    set: [product_name: :product_name]
end
```
