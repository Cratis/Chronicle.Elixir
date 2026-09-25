```elixir
defmodule MyApp.Events.DecNotRewindableOrderReceived do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-order-received"

  defstruct order_id: ""
end

defmodule MyApp.Events.DecNotRewindableOrderProcessing do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-order-processing"

  defstruct order_id: ""
end

defmodule MyApp.Events.DecNotRewindableOrderCompleted do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-order-completed"

  defstruct order_id: ""
end

defmodule MyApp.ReadModels.DecNotRewindableOrderStatus do
  use Chronicle.ReadModels.ReadModel

  defstruct status: nil, last_updated_at: nil
end

defmodule MyApp.Projections.DecNotRewindableRealTimeOrderStatusProjection do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecNotRewindableOrderStatus,
    not_rewindable: true,
    event_sequence: "order-processing",
    passive: true

  from_every set: [last_updated_at: :occurred]

  from MyApp.Events.DecNotRewindableOrderReceived,
    set: [status: "$value(RECEIVED)"]

  from MyApp.Events.DecNotRewindableOrderProcessing,
    set: [status: "$value(PROCESSING)"]

  from MyApp.Events.DecNotRewindableOrderCompleted,
    set: [status: "$value(COMPLETED)"]
end
```
