```elixir
defmodule MyApp.Events.ConstraintsDeclarativeIndexProjectCreated do
  use Cratis.Chronicle.Events.EventType, id: "constraints-declarative-index-project-created"
  defstruct name: ""
end

defmodule MyApp.Events.ConstraintsDeclarativeIndexProjectRemoved do
  use Cratis.Chronicle.Events.EventType, id: "constraints-declarative-index-project-removed"
  defstruct []
end

defmodule MyApp.Constraints.ConstraintsDeclarativeIndexUniqueProjectName do
  use Cratis.Chronicle.Events.Constraint

  unique name: "ConstraintsDeclarativeIndexUniqueProjectName" do
    on MyApp.Events.ConstraintsDeclarativeIndexProjectCreated, [:name]
    removed_with MyApp.Events.ConstraintsDeclarativeIndexProjectRemoved
  end
end
```
