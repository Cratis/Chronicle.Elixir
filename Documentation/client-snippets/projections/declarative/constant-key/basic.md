```elixir title="Constant key"
defmodule MyApp.Events.DecConstantKeyOrderPlaced do
  use Chronicle.Events.EventType, id: "dec-constant-key-order-placed"

  defstruct [:total]
end

defmodule MyApp.ReadModels.DecConstantKeyGlobalCounter do
  use Chronicle.ReadModels.ReadModel

  defstruct total_orders: 0
end

defmodule MyApp.Projections.DecConstantKeyGlobalCounterProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecConstantKeyGlobalCounter

  alias MyApp.Events.DecConstantKeyOrderPlaced

  from DecConstantKeyOrderPlaced,
    key: "global",
    count: :total_orders
end
```
