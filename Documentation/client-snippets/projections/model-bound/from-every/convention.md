```elixir
defmodule MyApp.Events.ProductRenamedForEveryConvention do
  use Chronicle.Events.EventType, id: "product-renamed-for-every-convention"

  defstruct name: "", version: 0
end

defmodule MyApp.Events.ProductPriceChangedForEveryConvention do
  use Chronicle.Events.EventType, id: "product-price-changed-for-every-convention"

  defstruct price: 0.0, version: 0
end

defmodule MyApp.ReadModels.ProductVersionFromEveryConvention do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, name: nil, price: 0.0, version: 0

  from MyApp.Events.ProductRenamedForEveryConvention,
    set: [id: :event_source_id]

  from MyApp.Events.ProductPriceChangedForEveryConvention

  from_every set: [version: :version]
end
```
