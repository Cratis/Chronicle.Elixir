```elixir title="Set a property from event context on every event"
defmodule MyApp.Events.InventoryRegisteredFromAll do
  use Chronicle.Events.EventType, id: "inventory-registered-from-all-v1"

  defstruct [:product_name]
end

defmodule MyApp.Events.InventoryAdjustedFromAll do
  use Chronicle.Events.EventType, id: "inventory-adjusted-from-all-v1"

  defstruct [:quantity]
end

defmodule MyApp.ReadModels.InventoryStatusFromAll do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{InventoryAdjustedFromAll, InventoryRegisteredFromAll}

  defstruct [:id, :product_name, :last_updated]

  from InventoryRegisteredFromAll,
    set: [id: :event_source_id, product_name: :product_name]

  from InventoryAdjustedFromAll

  from_every set: [last_updated: :occurred]
end
```
