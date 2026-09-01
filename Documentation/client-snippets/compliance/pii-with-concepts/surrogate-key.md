```elixir
# Surrogate key as event source identifier — no pii declared.
defmodule MyApp.Compliance.PiiWithConcepts.SurrogateEmployeeId do
  use Chronicle.Concept, type: :uuid, event_source_id: true
end

defmodule MyApp.Compliance.PiiWithConcepts.SurrogateNationalId do
  use Chronicle.Concept, type: :string
  pii("National ID number — sensitive personal identifier")
end

defmodule MyApp.Compliance.PiiWithConcepts.SurrogatePersonName do
  use Chronicle.Concept, type: :string
  pii()
end

# Sensitive values stored in PII-marked concept fields instead.
defmodule MyApp.Compliance.PiiWithConcepts.SurrogateEmployeeRegistered do
  use Chronicle.Events.EventType, id: "pii-with-concepts-surrogate-employee-registered"

  defstruct national_id: %MyApp.Compliance.PiiWithConcepts.SurrogateNationalId{},
            name: %MyApp.Compliance.PiiWithConcepts.SurrogatePersonName{}
end
```
