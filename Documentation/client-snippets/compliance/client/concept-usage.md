```elixir
defmodule MyApp.Compliance.Client.ConceptUsagePersonName do
  use Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.Client.EmployeeRegisteredWithConcept do
  use Chronicle.Events.EventType, id: "compliance-client-employee-registered-with-concept"

  defstruct name: %MyApp.Compliance.Client.ConceptUsagePersonName{}, department: ""
end

defmodule MyApp.Compliance.Client.EmployeeNameChanged do
  use Chronicle.Events.EventType, id: "compliance-client-employee-name-changed"

  # Also encrypted — reuses the same concept.
  defstruct new_name: %MyApp.Compliance.Client.ConceptUsagePersonName{}
end
```
