```elixir
defmodule MyApp.Events.MigrationsDotnetClientSplitPersonRegisteredV1 do
  use Cratis.Chronicle.Events.EventType, id: "dotnet-client-person-registered", generation: 1

  defstruct [:full_name]
end

defmodule MyApp.Events.MigrationsDotnetClientSplitPersonRegistered do
  use Cratis.Chronicle.Events.EventType, id: "dotnet-client-person-registered", generation: 2

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Migrations.MigrationsDotnetClientSplitPersonRegisteredMigration do
  use Cratis.Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientSplitPersonRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientSplitPersonRegistered, generation: 2}

  alias Cratis.Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.split_property(:full_name, :first_name, " ", 0)
    |> MigrationBuilder.split_property(:full_name, :last_name, " ", 1)
  end

  @impl true
  def downcast(builder) do
    MigrationBuilder.combine_properties(builder, [:first_name, :last_name], :full_name, " ")
  end
end
```
