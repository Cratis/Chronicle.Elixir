```elixir
defmodule MyApp.Events.NoAutoMapWorkArrangementSet do
  use Chronicle.Events.EventType, id: "no-auto-map-work-arrangement-set"

  defstruct location: "", work_mode: 0
end

defmodule MyApp.Events.NoAutoMapCandidateSubmitted do
  use Chronicle.Events.EventType, id: "no-auto-map-candidate-submitted"

  defstruct name: "", location: ""
end

defmodule MyApp.ReadModels.NoAutoMapAssignmentSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, location: nil, candidate_name: nil

  no_auto_map([:location])

  from MyApp.Events.NoAutoMapWorkArrangementSet,
    set: [id: :event_source_id, location: :location]

  from MyApp.Events.NoAutoMapCandidateSubmitted,
    set: [candidate_name: :name]
end
```
