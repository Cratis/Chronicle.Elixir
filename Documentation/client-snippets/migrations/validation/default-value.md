```elixir
defmodule MyApp.Events.MigrationsValidationAuthorRegisteredV1 do
  use Chronicle.Events.EventType, id: "validation-author-registered", generation: 1

  defstruct [:name]
end

defmodule MyApp.Events.MigrationsValidationAuthorRegistered do
  use Chronicle.Events.EventType, id: "validation-author-registered", generation: 2

  defstruct [:name, :status]
end

defmodule MyApp.Migrations.MigrationsValidationAuthorRegisteredMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsValidationAuthorRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsValidationAuthorRegistered, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    # name is unchanged between generations — no operation needed for it
    builder
    |> MigrationBuilder.default_value(:status, "active")
  end

  @impl true
  def downcast(builder) do
    # status does not exist in gen 1 — no mapping needed
    builder
  end
end
```
