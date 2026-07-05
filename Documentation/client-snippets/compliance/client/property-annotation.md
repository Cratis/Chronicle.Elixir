```elixir
defmodule MyApp.Events.ComplianceClientEmployeeRegistered do
  use Chronicle.Events.EventType, id: "compliance-client-employee-registered"

  defstruct [:first_name, :last_name, :department, :start_date]

  pii(:first_name)
  pii(:last_name)
end
```
