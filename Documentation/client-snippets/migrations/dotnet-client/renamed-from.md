```elixir
defmodule MyApp.Events.MigrationsDotnetClientRenamedFromCustomerRegisteredV1 do
  use Chronicle.Events.EventType, id: "dotnet-client-customer-registered", generation: 1

  defstruct [:email_address]
end

defmodule MyApp.Events.MigrationsDotnetClientRenamedFromCustomerRegistered do
  use Chronicle.Events.EventType, id: "dotnet-client-customer-registered", generation: 2

  defstruct [:email]
end

defmodule MyApp.Migrations.MigrationsDotnetClientRenamedFromCustomerRegisteredMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientRenamedFromCustomerRegisteredV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientRenamedFromCustomerRegistered, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder), do: MigrationBuilder.renamed_from(builder, :email, :email_address)

  @impl true
  def downcast(builder), do: MigrationBuilder.renamed_from(builder, :email_address, :email)
end
```
