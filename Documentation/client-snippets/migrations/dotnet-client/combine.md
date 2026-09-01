```elixir
defmodule MyApp.Events.MigrationsDotnetClientCombineShippingAddressRecordedV1 do
  use Chronicle.Events.EventType, id: "dotnet-client-shipping-address-recorded", generation: 1

  defstruct [:street, :city]
end

defmodule MyApp.Events.MigrationsDotnetClientCombineShippingAddressRecorded do
  use Chronicle.Events.EventType, id: "dotnet-client-shipping-address-recorded", generation: 2

  defstruct [:full_address]
end

defmodule MyApp.Migrations.MigrationsDotnetClientCombineShippingAddressRecordedMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsDotnetClientCombineShippingAddressRecordedV1, generation: 1},
    to: {MyApp.Events.MigrationsDotnetClientCombineShippingAddressRecorded, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    MigrationBuilder.combine_properties(builder, [:street, :city], :full_address, " ")
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.split_property(:full_address, :street, " ", 0)
    |> MigrationBuilder.split_property(:full_address, :city, " ", 1)
  end
end
```
