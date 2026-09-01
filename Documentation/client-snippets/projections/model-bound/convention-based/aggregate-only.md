```elixir title="Aggregating an event does not map its other properties"
defmodule MyApp.Events.AggOnlyArrangementSet do
  use Chronicle.Events.EventType, id: "agg-only-arrangement-set-v1"

  defstruct [:location]
end

defmodule MyApp.Events.AggOnlyCandidateSubmitted do
  use Chronicle.Events.EventType, id: "agg-only-candidate-submitted-v1"

  defstruct [:name, :location]
end

defmodule MyApp.ReadModels.AggOnlyAssignmentSummary do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{AggOnlyArrangementSet, AggOnlyCandidateSubmitted}

  defstruct [:location, candidate_count: 0]

  from AggOnlyArrangementSet

  # AggOnlyCandidateSubmitted is subscribed only to be counted, so its own
  # `location` field is never mapped over the value set from
  # AggOnlyArrangementSet.
  from AggOnlyCandidateSubmitted, count: :candidate_count
end
```
