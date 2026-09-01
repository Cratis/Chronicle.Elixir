```elixir
defmodule MyApp.Events.MigrationsDotnetClientMultiGenPersonRegisteredV1 do
  use Chronicle.Events.EventType, id: "dotnet-client-multi-gen-person-registered", generation: 1

  defstruct [:email_address, :name]
end

defmodule MyApp.Events.MigrationsDotnetClientMultiGenPersonRegisteredV2 do
  use Chronicle.Events.EventType, id: "dotnet-client-multi-gen-person-registered", generation: 2

  defstruct [:email, :name]
end

defmodule MyApp.Events.MigrationsDotnetClientMultiGenPersonRegistered do
  use Chronicle.Events.EventType, id: "dotnet-client-multi-gen-person-registered", generation: 3

  defstruct [:email, :first_name, :last_name]
end

# Generation 1 -> 2: rename email_address to email
defmodule MyApp.Migrations.MigrationsDotnetClientMultiGenPersonRegisteredV1ToV2 do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientMultiGenPersonRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientMultiGenPersonRegisteredV2, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder), do: MigrationBuilder.renamed_from(builder, :email, :email_address)

  @impl true
  def downcast(builder), do: MigrationBuilder.renamed_from(builder, :email_address, :email)
end

# Generation 2 -> 3: split name into first_name / last_name
defmodule MyApp.Migrations.MigrationsDotnetClientMultiGenPersonRegisteredV2ToV3 do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientMultiGenPersonRegisteredV2, generation: 2},
    to: {MyApp.Events.MigrationsDotnetClientMultiGenPersonRegistered, generation: 3}

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
