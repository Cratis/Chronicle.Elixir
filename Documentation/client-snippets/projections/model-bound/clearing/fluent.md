```elixir
defmodule MyApp.Events.MbClearingFluentNoted do
  use Chronicle.Events.EventType, id: "mb-clearing-fluent-noted"

  defstruct [:note]
end

defmodule MyApp.Events.MbClearingFluentCleared do
  use Chronicle.Events.EventType, id: "mb-clearing-fluent-cleared"

  defstruct []
end

defmodule MyApp.ReadModels.MbClearingFluentProject do
  use Chronicle.ReadModels.ReadModel

  defstruct project_id: nil, note: nil
end

defmodule MyApp.Projections.MbClearingFluentProjectProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.MbClearingFluentProject

  # Elixir has one projection language, not a separate attribute vs. fluent-builder split —
  # `clear_with/2` is available on a model-bound read model and on a declarative projection alike.
  from MyApp.Events.MbClearingFluentNoted, set: [note: :note]

  clear_with MyApp.Events.MbClearingFluentCleared, [:note]
end
```
