```elixir
defmodule MyApp.Events.MigrationsDotnetClientDefaultValueTaskCreatedV1 do
  use Chronicle.Events.EventType, id: "dotnet-client-task-created", generation: 1

  defstruct [:title]
end

defmodule MyApp.Events.MigrationsDotnetClientDefaultValueTaskCreated do
  use Chronicle.Events.EventType, id: "dotnet-client-task-created", generation: 2

  defstruct [:title, :status, :retry_count, :enabled]
end

defmodule MyApp.Migrations.MigrationsDotnetClientDefaultValueTaskCreatedMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientDefaultValueTaskCreatedV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientDefaultValueTaskCreated, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.default_value(:status, "active")
    |> MigrationBuilder.default_value(:retry_count, 0)
    |> MigrationBuilder.default_value(:enabled, true)
  end

  @impl true
  def downcast(builder) do
    # status, retry_count, and enabled did not exist in generation 1 — nothing to map back
    builder
  end
end
```
