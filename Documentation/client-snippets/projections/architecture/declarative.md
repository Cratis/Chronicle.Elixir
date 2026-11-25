```elixir
defmodule MyApp.Events.ArchitectureDeclarativeItemAdded do
  use Cratis.Chronicle.Events.EventType, id: "architecture-declarative-item-added"

  defstruct [:category]
end

defmodule MyApp.ReadModels.ArchitectureDeclarativeSummary do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct category: nil, count: 0
end

defmodule MyApp.Projections.ArchitectureDeclarativeSummaryProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.ArchitectureDeclarativeSummary

  from MyApp.Events.ArchitectureDeclarativeItemAdded,
    key: :category,
    count: :count
end
```
