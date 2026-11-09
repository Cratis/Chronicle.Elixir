```elixir title="Dictionary entries keyed by event content"
defmodule MyApp.Events.DecDictionarySeriesAssigned do
  use Chronicle.Events.EventType, id: "dec-dictionary-series-assigned"

  defstruct slot: "", series_id: ""
end

defmodule MyApp.Events.DecDictionarySlotCleared do
  use Chronicle.Events.EventType, id: "dec-dictionary-slot-cleared"

  defstruct slot: ""
end

defmodule MyApp.ReadModels.DecDictionarySchedule do
  use Chronicle.ReadModels.ReadModel

  defstruct series_by_slot: %{}
end

defmodule MyApp.Projections.DecDictionaryScheduleProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecDictionarySchedule

  alias MyApp.Events.{DecDictionarySeriesAssigned, DecDictionarySlotCleared}

  from DecDictionarySeriesAssigned,
    set: [series_by_slot: {:entry, {:event_content, :slot}, :series_id}]

  from DecDictionarySlotCleared,
    remove: [series_by_slot: {:event_content, :slot}]
end
```
