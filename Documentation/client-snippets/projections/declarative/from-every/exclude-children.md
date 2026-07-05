```elixir title="Exclude child projection events"
defmodule MyApp.Events.OrderCreatedDeclarativeEveryExclude do
  use Chronicle.Events.EventType, id: "order-created-declarative-every-exclude-v1"

  defstruct [:order_number]
end

defmodule MyApp.ReadModels.OrderAuditDeclarativeEveryExclude do
  use Chronicle.ReadModels.ReadModel

  defstruct [:order_number, :last_updated]
end

defmodule MyApp.Projections.OrderAuditDeclarativeEveryExcludeProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.OrderAuditDeclarativeEveryExclude

  alias MyApp.Events.OrderCreatedDeclarativeEveryExclude

  from OrderCreatedDeclarativeEveryExclude

  from_every set: [last_updated: :occurred], include_children: false
end
```
