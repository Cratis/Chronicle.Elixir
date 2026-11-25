```elixir title="Declarative FromAll with a dynamic dictionary key"
defmodule MyApp.Events.UserRegisteredForEventCounts do
  use Cratis.Chronicle.Events.EventType, id: "user-registered-for-event-counts-v1"

  defstruct [:name]
end

defmodule MyApp.Events.OrderPlacedForEventCounts do
  use Cratis.Chronicle.Events.EventType, id: "order-placed-for-event-counts-v1"

  defstruct [:order_id]
end

defmodule MyApp.ReadModels.EventTypeCountsReadModel do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:event_count_by_type]
end

defmodule MyApp.Projections.EventTypeCountsProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.EventTypeCountsReadModel

  from_every increment: [event_count_by_type: {:event_context, :type}]
end
```
