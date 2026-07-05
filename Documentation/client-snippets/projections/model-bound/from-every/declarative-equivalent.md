```elixir title="Declarative projection with every-event metadata"
defmodule MyApp.Events.InventoryRegisteredDeclarativeForEvery do
  use Chronicle.Events.EventType, id: "inventory-registered-declarative-for-every-v1"

  defstruct [:product_name]
end

defmodule MyApp.Events.InventoryAdjustedDeclarativeForEvery do
  use Chronicle.Events.EventType, id: "inventory-adjusted-declarative-for-every-v1"

  defstruct [:quantity]
end

defmodule MyApp.ReadModels.InventoryStatusDeclarativeFromEvery do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :product_name, :last_updated]
end

defmodule MyApp.Projections.InventoryStatusDeclarativeProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.InventoryStatusDeclarativeFromEvery

  alias MyApp.Events.{InventoryAdjustedDeclarativeForEvery, InventoryRegisteredDeclarativeForEvery}

  from InventoryRegisteredDeclarativeForEvery,
    set: [
      id: :event_source_id,
      product_name: :product_name
    ]

  from InventoryAdjustedDeclarativeForEvery

  from_every set: [last_updated: :occurred]
end
```
