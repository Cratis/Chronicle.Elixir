```elixir
defmodule MyApp.Events.DecEventContextUserActionForKey do
  use Chronicle.Events.EventType, id: "dec-event-context-user-action-for-key"

  defstruct [:user_id, :action_type]
end

defmodule MyApp.ReadModels.DecEventContextEventLogKey do
  defstruct [:date, :sequence_number]
end

defmodule MyApp.ReadModels.DecEventContextEventLogEntry do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :action_type, :user_id]
end

defmodule MyApp.Projections.DecEventContextEventLogProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecEventContextEventLogEntry

  alias MyApp.Events.DecEventContextUserActionForKey

  from DecEventContextUserActionForKey,
    key:
      {:composite,
       [
         date: {:event_context, "Occurred"},
         sequence_number: {:event_context, "SequenceNumber"}
       ]}
end
```
