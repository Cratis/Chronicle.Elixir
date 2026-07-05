```elixir
defmodule MyApp.Events.MigrationsRenamePaymentProcessedV1 do
  use Chronicle.Events.EventType, id: "payment-processed", generation: 1

  defstruct [:old_amount]
end

defmodule MyApp.Events.MigrationsRenamePaymentProcessed do
  use Chronicle.Events.EventType, id: "payment-processed", generation: 2

  defstruct [:amount]
end

defmodule MyApp.Migrations.MigrationsRenamePaymentProcessedMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsRenamePaymentProcessedV1, generation: 1},
    to: {MyApp.Events.MigrationsRenamePaymentProcessed, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:old_amount, :amount)
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:amount, :old_amount)
  end
end
```
