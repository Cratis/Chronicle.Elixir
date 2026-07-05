```elixir
defmodule MyApp.Events.MigrationsSplitPersonRegisteredV1 do
  use Chronicle.Events.EventType, id: "person-registered", generation: 1

  defstruct [:full_name]
end

defmodule MyApp.Events.MigrationsSplitPersonRegistered do
  use Chronicle.Events.EventType, id: "person-registered", generation: 2

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Migrations.MigrationsSplitPersonRegisteredMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsSplitPersonRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsSplitPersonRegistered, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    # Gets first part
    |> MigrationBuilder.split_property(:full_name, :first_name, " ", 0)
    # Gets second part
    |> MigrationBuilder.split_property(:full_name, :last_name, " ", 1)
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.combine_properties([:first_name, :last_name], :full_name, " ")
  end
end
```
