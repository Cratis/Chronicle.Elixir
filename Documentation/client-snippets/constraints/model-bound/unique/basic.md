```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueProjectCreated do
  use Chronicle.Events.EventType, id: "constraints-model-bound-unique-project-created"

  defstruct [:name, :description]

  unique(:name)
end
```
