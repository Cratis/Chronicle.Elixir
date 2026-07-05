```elixir
defmodule MyApp.Events.PiiAttrEmployeeRegistered do
  use Chronicle.Events.EventType, id: "pii-attr-employee-registered"

  defstruct [:first_name, :last_name, :department]

  pii(:first_name)
  pii(:last_name)
end
```
