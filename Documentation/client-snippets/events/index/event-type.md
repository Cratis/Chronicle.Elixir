```elixir
defmodule MyApp.Events.EventsIndexTypeEmployeeRegistered do
  use Cratis.Chronicle.Events.EventType, id: "events-index-type-employee-registered"

  defstruct [:first_name, :last_name]
end
```
