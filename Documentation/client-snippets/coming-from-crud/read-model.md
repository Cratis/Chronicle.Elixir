```elixir
defmodule MyApp.ReadModels.CrudComparisonCustomerCard do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{CrudComparisonCustomerRegistered, CrudComparisonAddressChanged}

  defstruct id: nil, name: nil, address: nil, times_relocated: 0

  from CrudComparisonCustomerRegistered,
    set: [id: :event_source_id, name: :name, address: :address]

  from CrudComparisonAddressChanged,
    set: [address: :address],
    count: :times_relocated
end
```
