```elixir title="Update an audit timestamp from every event"
defmodule MyApp.Events.InventoryProductRegisteredForEvery do
  use Chronicle.Events.EventType, id: "inventory-product-registered-for-every-v1"

  defstruct [:product_name]
end

defmodule MyApp.Events.InventoryItemsAdjustedForEvery do
  use Chronicle.Events.EventType, id: "inventory-items-adjusted-for-every-v1"

  defstruct [:quantity]
end

defmodule MyApp.ReadModels.InventoryStatusFromEvery do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{InventoryItemsAdjustedForEvery, InventoryProductRegisteredForEvery}

  defstruct [:id, :product_name, :last_updated]

  from InventoryProductRegisteredForEvery,
    set: [
      id: :event_source_id,
      product_name: :product_name
    ]

  from InventoryItemsAdjustedForEvery

  from_every set: [last_updated: :occurred]
end
```
