```elixir title="Specific context vs every event"
defmodule MyApp.Events.OrderPlacedForLifecycle do
  use Chronicle.Events.EventType, id: "order-placed-for-lifecycle-v1"

  defstruct [:customer_name]
end

defmodule MyApp.Events.OrderShippedForLifecycle do
  use Chronicle.Events.EventType, id: "order-shipped-for-lifecycle-v1"

  defstruct [:tracking_number]
end

defmodule MyApp.ReadModels.OrderLifecycle do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{OrderPlacedForLifecycle, OrderShippedForLifecycle}

  defstruct [:id, :placed_at, :shipped_at, :last_modified]

  from OrderPlacedForLifecycle,
    set: [
      id: :event_source_id,
      placed_at: :occurred
    ]

  from OrderShippedForLifecycle,
    set: [shipped_at: :occurred]

  from_every set: [last_modified: :occurred]
end
```
