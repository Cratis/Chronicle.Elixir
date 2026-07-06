```elixir title="Multiple joins"
defmodule MyApp.Events.DecJoinsMultipleEmployeeAssigned do
  use Chronicle.Events.EventType, id: "dec-joins-multiple-employee-assigned"

  defstruct [:group_id, :department_id, :location_id]
end

defmodule MyApp.Events.DecJoinsMultipleGroupCreated do
  use Chronicle.Events.EventType, id: "dec-joins-multiple-group-created"

  defstruct [:name]
end

defmodule MyApp.Events.DecJoinsMultipleDepartmentCreated do
  use Chronicle.Events.EventType, id: "dec-joins-multiple-department-created"

  defstruct [:name]
end

defmodule MyApp.Events.DecJoinsMultipleLocationUpdated do
  use Chronicle.Events.EventType, id: "dec-joins-multiple-location-updated"

  defstruct [:address]
end

defmodule MyApp.ReadModels.DecJoinsMultipleEmployeeSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct [:group_id, :group_name, :department_id, :department_name, :location_id, :location_address]
end

defmodule MyApp.Projections.DecJoinsMultipleEmployeeSummaryProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecJoinsMultipleEmployeeSummary

  alias MyApp.Events.{
    DecJoinsMultipleEmployeeAssigned,
    DecJoinsMultipleGroupCreated,
    DecJoinsMultipleDepartmentCreated,
    DecJoinsMultipleLocationUpdated
  }

  from DecJoinsMultipleEmployeeAssigned

  join DecJoinsMultipleGroupCreated, on: :group_id
  join DecJoinsMultipleDepartmentCreated, on: :department_id
  join DecJoinsMultipleLocationUpdated, on: :location_id
end
```
