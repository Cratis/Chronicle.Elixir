```elixir
defmodule MyApp.Events.MigrationsCombineShippingAddressRecordedV1 do
  use Chronicle.Events.EventType, id: "shipping-address-recorded", generation: 1

  defstruct [:street, :city]
end

defmodule MyApp.Events.MigrationsCombineShippingAddressRecorded do
  use Chronicle.Events.EventType, id: "shipping-address-recorded", generation: 2

  defstruct [:formatted_address]
end

defmodule MyApp.Migrations.MigrationsCombineShippingAddressRecordedMigration do
  use Chronicle.Events.Migration,
    from: {MyApp.Events.MigrationsCombineShippingAddressRecordedV1, generation: 1},
    to: {MyApp.Events.MigrationsCombineShippingAddressRecorded, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    # Joins with space separator
    |> MigrationBuilder.combine_properties([:street, :city], :formatted_address, " ")
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.split_property(:formatted_address, :street, " ", 0)
    |> MigrationBuilder.split_property(:formatted_address, :city, " ", 1)
  end
end
```
