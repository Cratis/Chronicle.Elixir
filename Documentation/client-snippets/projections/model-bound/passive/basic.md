```elixir
defmodule MyApp.Events.PassiveSnapshotCreated do
  use Chronicle.Events.EventType, id: "passive-snapshot-created-v1"

  defstruct [:data]
end

defmodule MyApp.ReadModels.PassiveHistoricalSnapshot do
  use Chronicle.ReadModels.ReadModel, passive: true

  alias MyApp.Events.PassiveSnapshotCreated

  defstruct [:id, :data]

  from PassiveSnapshotCreated,
    set: [id: :event_source_id, data: :data]
end
```
