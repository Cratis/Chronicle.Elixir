```elixir
defmodule MyApp.Events.CountersItemCreated do
  use Chronicle.Events.EventType, id: "counters-item-created-v1"

  defstruct [:name, :initial_quantity]
end

defmodule MyApp.Events.CountersItemRestocked do
  use Chronicle.Events.EventType, id: "counters-item-restocked-v1"

  defstruct []
end

defmodule MyApp.Events.CountersItemSold do
  use Chronicle.Events.EventType, id: "counters-item-sold-v1"

  defstruct []
end

defmodule MyApp.ReadModels.CountersInventoryItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{CountersItemCreated, CountersItemRestocked, CountersItemSold}

  defstruct [:item_id, :name, quantity: 0, restock_count: 0, sales_count: 0]

  from CountersItemCreated,
    set: [item_id: :event_source_id, name: :name, quantity: :initial_quantity]

  from CountersItemRestocked,
    add: [quantity: 1],
    count: :restock_count

  from CountersItemSold,
    subtract: [quantity: 1],
    count: :sales_count
end
```
