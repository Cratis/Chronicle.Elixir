```elixir
defmodule MyApp.Compliance.ReadModels.ReducerPersonName do
  use Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.ReadModels.PatientAdmitted do
  use Chronicle.Events.EventType, id: "compliance-read-models-patient-admitted"

  defstruct name: %MyApp.Compliance.ReadModels.ReducerPersonName{}, admitted_at: nil
end

defmodule MyApp.Compliance.ReadModels.PatientSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct patient_id: nil, name: "", last_admitted_at: nil

  # A reducer assigns name as a plain string, so it needs its own explicit
  # pii/1,2 declaration — it is not itself a Chronicle.Concept field here.
  pii(:name)
end

defmodule MyApp.Compliance.ReadModels.PatientSummaryReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.Compliance.ReadModels.PatientSummary

  @handles MyApp.Compliance.ReadModels.PatientAdmitted

  @impl true
  def reduce(%MyApp.Compliance.ReadModels.PatientAdmitted{} = event, _model, context) do
    %MyApp.Compliance.ReadModels.PatientSummary{
      patient_id: context.event_source_id,
      name: event.name,
      last_admitted_at: context.occurred
    }
  end
end
```
