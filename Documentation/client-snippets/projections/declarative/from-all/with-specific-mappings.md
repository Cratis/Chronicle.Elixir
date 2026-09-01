```elixir title="Combine from_every with event-specific mappings"
defmodule MyApp.Events.OrderCreatedDeclarativeAll do
  use Chronicle.Events.EventType, id: "order-created-declarative-all"

  defstruct [:order_number]
end

defmodule MyApp.Events.OrderShippedDeclarativeAll do
  use Chronicle.Events.EventType, id: "order-shipped-declarative-all"

  defstruct [:tracking_number]
end

defmodule MyApp.ReadModels.OrderDeclarativeAll do
  use Chronicle.ReadModels.ReadModel

  defstruct [:order_number, :status, :last_modified]
end

defmodule MyApp.Projections.OrderDeclarativeAllProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.OrderDeclarativeAll

  alias MyApp.Events.{OrderCreatedDeclarativeAll, OrderShippedDeclarativeAll}

  # Elixir's from_every excludes child-projection events by default — the
  # same default FromAll uses in .NET.
  from_every set: [last_modified: :occurred]

  from OrderCreatedDeclarativeAll,
    set: [
      order_number: :order_number,
      status: "$value(Placed)"
    ]

  from OrderShippedDeclarativeAll,
    set: [status: "$value(Shipped)"]
end
```
