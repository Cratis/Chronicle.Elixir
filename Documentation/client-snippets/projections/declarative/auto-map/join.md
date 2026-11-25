```elixir title="AutoMap with a join"
defmodule MyApp.Events.AutoMapEmployeeHired do
  use Cratis.Chronicle.Events.EventType, id: "auto-map-employee-hired"

  defstruct [:employee_name, :department_id]
end

defmodule MyApp.Events.AutoMapDepartmentRenamed do
  use Cratis.Chronicle.Events.EventType, id: "auto-map-department-renamed"

  defstruct [:department_name]
end

defmodule MyApp.ReadModels.AutoMapEmployee do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:employee_name, :department_id, :department_name]
end

defmodule MyApp.Projections.AutoMapEmployeeProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.AutoMapEmployee

  alias MyApp.Events.{AutoMapEmployeeHired, AutoMapDepartmentRenamed}

  from AutoMapEmployeeHired

  join AutoMapDepartmentRenamed, on: :department_id
end
```
