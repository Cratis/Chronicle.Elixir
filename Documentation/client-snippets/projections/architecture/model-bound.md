```elixir
defmodule MyApp.Events.ArchitectureModelBoundItemAdded do
  use Chronicle.Events.EventType

  defstruct [:category]
end

defmodule MyApp.ReadModels.ArchitectureModelBoundSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct category: nil, count: 0

  from MyApp.Events.ArchitectureModelBoundItemAdded,
    key: :category,
    count: :count
end
```
