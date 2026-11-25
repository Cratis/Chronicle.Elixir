```elixir
defmodule MyApp.Events.DecFromEventSequencePackageCreated do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-package-created"

  defstruct package_id: ""
end

defmodule MyApp.Events.DecFromEventSequencePackageShipped do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-package-shipped"

  defstruct package_id: "", shipped_at: ""
end

defmodule MyApp.Events.DecFromEventSequencePackageDelivered do
  use Cratis.Chronicle.Events.EventType, id: "dec-from-event-sequence-package-delivered"

  defstruct package_id: "", delivered_at: ""
end

defmodule MyApp.ReadModels.DecFromEventSequenceShipping do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct package_id: nil, shipped_at: nil, delivered_at: nil
end

defmodule MyApp.Projections.DecFromEventSequenceMultiOrderProjection do
  use Cratis.Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecFromEventSequenceOrder,
    event_sequence: "order-management"

  from MyApp.Events.DecFromEventSequenceOrderCreated,
    set: [status: "$value(Created)"]
end

defmodule MyApp.Projections.DecFromEventSequenceShippingProjection do
  use Cratis.Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecFromEventSequenceShipping,
    event_sequence: "shipping-management"

  from MyApp.Events.DecFromEventSequencePackageCreated
  from MyApp.Events.DecFromEventSequencePackageShipped
  from MyApp.Events.DecFromEventSequencePackageDelivered
end
```
