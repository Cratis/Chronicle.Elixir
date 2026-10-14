```elixir
defmodule MyApp.Events.MigrationsDotnetClientAuthorRegistered do
  use Chronicle.Events.EventType, id: "dotnet-client-author-registered", generation: 2

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Events.MigrationsDotnetClientAuthorRegisteredV1 do
  use Chronicle.Events.EventType,
    generation_for: MyApp.Events.MigrationsDotnetClientAuthorRegistered,
    generation: 1

  defstruct [:name]
end
```
