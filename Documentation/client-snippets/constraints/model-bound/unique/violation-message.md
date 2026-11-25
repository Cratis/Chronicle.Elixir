```elixir
defmodule MyApp.Events.ConstraintsModelBoundUniqueMessageProjectCreated do
  use Cratis.Chronicle.Events.EventType, id: "constraints-model-bound-unique-message-project-created"

  defstruct [:name, :description]

  unique(:name, message: "A project with this name already exists.")
end
```
