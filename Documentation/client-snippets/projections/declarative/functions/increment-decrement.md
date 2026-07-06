```elixir title="Increment/decrement functions"
defmodule MyApp.Events.DecFunctionsItemAdded do
  use Chronicle.Events.EventType, id: "dec-functions-item-added"

  defstruct [:name]
end

defmodule MyApp.Events.DecFunctionsItemRemoved do
  use Chronicle.Events.EventType, id: "dec-functions-item-removed"

  defstruct [:name]
end

defmodule MyApp.ReadModels.DecFunctionsInventory do
  use Chronicle.ReadModels.ReadModel

  defstruct quantity: 0
end

defmodule MyApp.Projections.DecFunctionsInventoryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecFunctionsInventory

  alias MyApp.Events.{DecFunctionsItemAdded, DecFunctionsItemRemoved}

  from DecFunctionsItemAdded,
    add: [quantity: 1]

  from DecFunctionsItemRemoved,
    subtract: [quantity: 1]
end
```
