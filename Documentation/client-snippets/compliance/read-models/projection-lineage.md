```elixir
defmodule MyApp.Compliance.ReadModels.PersonName do
  use Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.ReadModels.EmployeeRegistered do
  use Chronicle.Events.EventType, id: "compliance-read-models-employee-registered"

  defstruct name: %MyApp.Compliance.ReadModels.PersonName{}, department: ""
end

defmodule MyApp.Compliance.ReadModels.Employee do
  use Chronicle.ReadModels.ReadModel

  # name reuses the same concept as the source event, so it is stored
  # encrypted at rest without repeating the pii declaration here.
  defstruct id: nil, name: %MyApp.Compliance.ReadModels.PersonName{}, department: nil

  from MyApp.Compliance.ReadModels.EmployeeRegistered,
    set: [id: :event_source_id, name: :name, department: :department]
end
```
