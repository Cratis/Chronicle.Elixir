```elixir
defmodule MyApp.Events.ConstraintsUniqueProjectCreated do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-project-created"

  unique :name, name: "ConstraintsUniqueProjectName"

  defstruct name: ""
end

defmodule MyApp.Events.ConstraintsUniqueProjectRemoved do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-project-removed"

  remove_constraint "ConstraintsUniqueProjectName"

  defstruct []
end
```
