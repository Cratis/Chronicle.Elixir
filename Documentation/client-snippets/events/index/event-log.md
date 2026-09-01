```elixir
defmodule MyApp.Events.EventsIndexEmployeeRegistered do
  use Chronicle.Events.EventType, id: "events-index-employee-registered"

  defstruct [:first_name, :last_name]
end

defmodule MyApp.EventsIndexEmployeesService do
  alias MyApp.Events.EventsIndexEmployeeRegistered

  def register_employee(employee_id, first_name, last_name) do
    Chronicle.append(employee_id, %EventsIndexEmployeeRegistered{
      first_name: first_name,
      last_name: last_name
    })
  end
end
```
