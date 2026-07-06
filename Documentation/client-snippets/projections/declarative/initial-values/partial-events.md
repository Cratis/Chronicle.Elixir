```elixir title="Defaults for fields events do not set"
defmodule MyApp.Events.InitialValuesStockReceived do
  use Chronicle.Events.EventType, id: "initial-values-stock-received"

  defstruct [:quantity]
end

defmodule MyApp.Events.InitialValuesStockReserved do
  use Chronicle.Events.EventType, id: "initial-values-stock-reserved"

  defstruct [:quantity]
end

defmodule MyApp.ReadModels.InitialValuesInventoryItem do
  use Chronicle.ReadModels.ReadModel

  defstruct current_stock: 0,
            reserved_stock: 0,
            last_updated: nil,
            minimum_level: 10,
            maximum_level: 1000,
            reorder_point: 20
end

defmodule MyApp.Projections.InitialValuesInventoryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.InitialValuesInventoryItem

  alias MyApp.Events.{InitialValuesStockReceived, InitialValuesStockReserved}

  from InitialValuesStockReceived,
    add: [current_stock: :quantity],
    set: [last_updated: :occurred]

  from InitialValuesStockReserved,
    add: [reserved_stock: :quantity],
    set: [last_updated: :occurred]
end
```
