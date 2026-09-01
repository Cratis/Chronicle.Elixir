```elixir
defmodule MyApp.Events.ComingFromCrudWriteAndReadAddressChanged do
  use Chronicle.Events.EventType, id: "crud-comparison-write-and-read-address-changed"

  defstruct [:address]
end

defmodule MyApp.ReadModels.ComingFromCrudWriteAndReadCustomerCard do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ComingFromCrudWriteAndReadAddressChanged

  defstruct id: nil, address: nil

  from ComingFromCrudWriteAndReadAddressChanged,
    set: [id: :event_source_id, address: :address]
end

defmodule MyApp.ComingFromCrudCustomerAddressUpdater do
  alias MyApp.Events.ComingFromCrudWriteAndReadAddressChanged
  alias MyApp.ReadModels.ComingFromCrudWriteAndReadCustomerCard

  def change_address(customer_id, new_address) do
    :ok =
      Chronicle.append(customer_id, %ComingFromCrudWriteAndReadAddressChanged{
        address: new_address
      })

    Chronicle.read_model(ComingFromCrudWriteAndReadCustomerCard, customer_id)
  end
end
```
