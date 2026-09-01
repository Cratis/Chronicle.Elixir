```elixir title="Every-event mapping alongside per-event convention mapping"
defmodule MyApp.Events.ProductRenamedFromAllConvention do
  use Chronicle.Events.EventType, id: "product-renamed-from-all-convention-v1"

  defstruct [:name, :version]
end

defmodule MyApp.Events.ProductPriceChangedFromAllConvention do
  use Chronicle.Events.EventType, id: "product-price-changed-from-all-convention-v1"

  defstruct [:price, :version]
end

defmodule MyApp.ReadModels.ProductVersionFromAllConvention do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{ProductPriceChangedFromAllConvention, ProductRenamedFromAllConvention}

  defstruct [:id, :name, :price, :version]

  from ProductRenamedFromAllConvention,
    set: [id: :event_source_id, name: :name]

  from ProductPriceChangedFromAllConvention,
    set: [id: :event_source_id, price: :price]

  # `version` is carried by every event in this projection, so it is mapped
  # once for all of them instead of being repeated in each `from`.
  from_every set: [version: :version]
end
```
