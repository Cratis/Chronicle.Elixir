```elixir
# Property-level: requires repeating pii/1,2 on every event.
defmodule MyApp.Compliance.PiiWithConcepts.EmployeeRegisteredComparison do
  use Chronicle.Events.EventType, id: "pii-with-concepts-employee-registered-comparison"
  defstruct [:name, :department]

  pii(:name)
end

defmodule MyApp.Compliance.PiiWithConcepts.EmployeeNameChangedComparison do
  use Chronicle.Events.EventType, id: "pii-with-concepts-employee-name-changed-comparison"
  defstruct [:new_name]

  # Easy to forget — a plaintext value would be written with no warning.
  pii(:new_name)
end

# Concept-level: declare once, apply everywhere automatically.
defmodule MyApp.Compliance.PiiWithConcepts.PersonNameComparison do
  use Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.PiiWithConcepts.EmployeeRegisteredComparisonGood do
  use Chronicle.Events.EventType, id: "pii-with-concepts-employee-registered-comparison-good"

  defstruct name: %MyApp.Compliance.PiiWithConcepts.PersonNameComparison{}, department: ""
end

defmodule MyApp.Compliance.PiiWithConcepts.EmployeeNameChangedComparisonGood do
  use Chronicle.Events.EventType, id: "pii-with-concepts-employee-name-changed-comparison-good"

  # Also encrypted — no extra annotation needed.
  defstruct new_name: %MyApp.Compliance.PiiWithConcepts.PersonNameComparison{}
end
```
