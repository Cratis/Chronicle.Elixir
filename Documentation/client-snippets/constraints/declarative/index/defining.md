```elixir
defmodule MyApp.Events.ConstraintsDeclarativeIndexProjectCreated do
  use Chronicle.Events.EventType, id: "constraints-declarative-index-project-created"

  unique :name, name: "ConstraintsDeclarativeIndexUniqueProjectName"

  defstruct name: ""
end

defmodule MyApp.Events.ConstraintsDeclarativeIndexProjectRemoved do
  use Chronicle.Events.EventType, id: "constraints-declarative-index-project-removed"

  remove_constraint "ConstraintsDeclarativeIndexUniqueProjectName"

  defstruct []
end
```
