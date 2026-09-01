```elixir
defmodule MyApp.Events.MigrationsDotnetClientMigratorAuthorRegisteredV1 do
  use Chronicle.Events.EventType, id: "dotnet-client-migrator-author-registered", generation: 1

  defstruct [:name]
end

defmodule MyApp.Events.MigrationsDotnetClientMigratorAuthorRegistered do
  use Chronicle.Events.EventType, id: "dotnet-client-migrator-author-registered", generation: 2

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Migrations.MigrationsDotnetClientMigratorAuthorRegisteredMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientMigratorAuthorRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientMigratorAuthorRegistered, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.split_property(:name, :first_name, " ", 0)
    |> MigrationBuilder.split_property(:name, :last_name, " ", 1)
  end

  @impl true
  def downcast(builder) do
    MigrationBuilder.combine_properties(builder, [:first_name, :last_name], :name, " ")
  end
end
```
