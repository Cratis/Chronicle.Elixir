```elixir
defmodule MyApp.DecFromEventSequenceEventSequences do
  def order_management, do: "order-management"
end

defmodule MyApp.Projections.DecFromEventSequenceOrderProjectionWithConstant do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecFromEventSequenceOrder,
    event_sequence: MyApp.DecFromEventSequenceEventSequences.order_management()

  from MyApp.Events.DecFromEventSequenceOrderCreated
end
```
