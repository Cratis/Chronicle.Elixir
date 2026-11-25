```elixir
defmodule MyApp.Events.MigrationsAuthorRegisteredV1 do
  use Cratis.Chronicle.Events.EventType, id: "author-registered", generation: 1

  defstruct [:name]
end

defmodule MyApp.Events.MigrationsAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "author-registered", generation: 2

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Migrations.MigrationsAuthorRegisteredMigration do
  use Cratis.Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsAuthorRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsAuthorRegistered, generation: 2}

  alias Cratis.Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.split_property(:name, :first_name, " ", 0)
    |> MigrationBuilder.split_property(:name, :last_name, " ", 1)
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.combine_properties([:first_name, :last_name], :name, " ")
  end
end
```
