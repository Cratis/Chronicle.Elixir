```elixir
defmodule MyApp.Events.ConstraintsUniqueMessageProjectCreated do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-message-project-created"
  defstruct name: ""
end

defmodule MyApp.Constraints.ConstraintsUniqueMessageProjectName do
  use Cratis.Chronicle.Events.Constraint

  unique name: "ConstraintsUniqueMessageProjectName",
    message: "A project with this name already exists." do
    on MyApp.Events.ConstraintsUniqueMessageProjectCreated, [:name]
  end
end
```
