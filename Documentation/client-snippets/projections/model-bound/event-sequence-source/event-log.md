```elixir
defmodule MyApp.Events.MbEventSeqLocalEvent do
  use Chronicle.Events.EventType, id: "mb-event-seq-local-event"

  defstruct data: ""
end

defmodule MyApp.ReadModels.MbEventSeqLocalSnapshot do
  use Chronicle.ReadModels.ReadModel, event_sequence: "event-log"

  defstruct id: nil, data: nil

  from MyApp.Events.MbEventSeqLocalEvent,
    set: [id: :event_source_id, data: :data]
end
```
