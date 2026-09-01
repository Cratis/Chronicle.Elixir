```elixir title="Aggregating an event does not map its other properties"
defmodule MyApp.Events.DeclAggArrangementSet do
  use Chronicle.Events.EventType, id: "decl-agg-arrangement-set-v1"

  defstruct [:location]
end

defmodule MyApp.Events.DeclAggCandidateSubmitted do
  use Chronicle.Events.EventType, id: "decl-agg-candidate-submitted-v1"

  defstruct [:name, :location]
end

defmodule MyApp.ReadModels.DeclAggAssignmentSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct [:location, candidate_count: 0]
end

defmodule MyApp.Projections.DeclAggAssignmentProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DeclAggAssignmentSummary

  alias MyApp.Events.{DeclAggArrangementSet, DeclAggCandidateSubmitted}

  from DeclAggArrangementSet

  # DeclAggCandidateSubmitted is subscribed only to be counted, so its own
  # `location` field is never mapped over the value set from
  # DeclAggArrangementSet.
  from DeclAggCandidateSubmitted, count: :candidate_count
end
```
