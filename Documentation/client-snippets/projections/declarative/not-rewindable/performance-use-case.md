```elixir
defmodule MyApp.Events.DecNotRewindableApiRequestCompleted do
  use Chronicle.Events.EventType, id: "dec-not-rewindable-api-request-completed"

  defstruct endpoint: "", status_code: 0, duration_milliseconds: 0
end

defmodule MyApp.ReadModels.DecNotRewindablePerformanceMetric do
  use Chronicle.ReadModels.ReadModel

  defstruct timestamp: nil
end

defmodule MyApp.Projections.DecNotRewindablePerformanceMetricProjection do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.DecNotRewindablePerformanceMetric,
    not_rewindable: true

  from MyApp.Events.DecNotRewindableApiRequestCompleted,
    set: [timestamp: :occurred]
end
```
