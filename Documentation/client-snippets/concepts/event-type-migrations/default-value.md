```elixir
defmodule MyApp.Events.MigrationsDefaultValueOrderShippedV1 do
  use Chronicle.Events.EventType, id: "order-shipped", generation: 1

  defstruct [:tracking_number]
end

defmodule MyApp.Events.MigrationsDefaultValueOrderShipped do
  use Chronicle.Events.EventType, id: "order-shipped", generation: 2

  defstruct [:tracking_number, :retry_count, :description]
end

defmodule MyApp.Migrations.MigrationsDefaultValueOrderShippedMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDefaultValueOrderShippedV1, generation: 1},
    to: {MyApp.Events.MigrationsDefaultValueOrderShipped, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.default_value(:retry_count, 42)
    |> MigrationBuilder.default_value(:description, "default string")
  end

  @impl true
  def downcast(builder) do
    # retry_count and description did not exist in generation 1 — nothing to map back
    builder
  end
end
```
