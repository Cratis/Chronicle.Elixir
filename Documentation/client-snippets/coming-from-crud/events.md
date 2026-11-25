```elixir
defmodule MyApp.Events.CrudComparisonCustomerRegistered do
  use Cratis.Chronicle.Events.EventType, id: "crud-comparison-customer-registered"

  defstruct [:name, :address]
end

defmodule MyApp.Events.CrudComparisonAddressChanged do
  use Cratis.Chronicle.Events.EventType, id: "crud-comparison-address-changed"

  defstruct [:address]
end
```
