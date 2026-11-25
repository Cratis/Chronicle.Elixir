```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueProjectCreated do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-project-created"

  defstruct [:name, :description]

  unique(:name)
end
```
