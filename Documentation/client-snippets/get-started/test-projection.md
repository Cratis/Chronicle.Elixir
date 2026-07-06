```elixir title="The projection - builds queryable state"
defmodule MyApp.ReadModels.TestProjection do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.TestEvent

  defstruct [:id, :message]

  from TestEvent,
    set: [
      id: :event_source_id,
      message: :message
    ]
end
```
