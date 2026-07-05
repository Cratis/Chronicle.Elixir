```elixir
defmodule MyApp.Events.SetValueThingHappened do
  use Chronicle.Events.EventType, id: "set-value-thing-happened-v1"

  defstruct []
end

defmodule MyApp.ReadModels.SetValueThing do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.SetValueThingHappened

  defstruct [:id, status_label: "", priority: 0, is_active: false, score: 0.0]

  from SetValueThingHappened,
    set: [
      id: :event_source_id,
      status_label: "$value(pending)",
      priority: 42,
      is_active: true,
      score: "$value(3.14)"
    ]
end
```
