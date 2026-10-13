```elixir
defmodule MyApp.Events.DecEventContextActivityPerformed do
  use Chronicle.Events.EventType, id: "dec-event-context-activity-performed"

  defstruct [:activity_id, :activity_type]
end

defmodule MyApp.ReadModels.DecEventContextActivityLogEntry do
  use Chronicle.ReadModels.ReadModel

  defstruct activity_id: nil, timestamp: nil, sequence_number: 0
end

defmodule MyApp.ReadModels.DecEventContextUserWithActivityLog do
  use Chronicle.ReadModels.ReadModel,
    types: [activity_log: {:list, MyApp.ReadModels.DecEventContextActivityLogEntry}]

  defstruct activity_log: []
end

defmodule MyApp.Projections.DecEventContextUserActivityLogProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecEventContextUserWithActivityLog

  children :activity_log, identified_by: :activity_id do
    from MyApp.Events.DecEventContextActivityPerformed,
      key: :activity_id,
      set: [
        activity_id: :activity_id,
        timestamp: :occurred,
        sequence_number: "$eventContext(SequenceNumber)"
      ]
  end
end
```
