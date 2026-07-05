```elixir
defmodule MyApp.ModelingEventsCustomerName do
  defstruct [:value]
end

defmodule MyApp.ModelingEventsEmail do
  defstruct [:value]
end

defmodule MyApp.ModelingEventsDeactivationReason do
  defstruct [:value]
end

defmodule MyApp.ModelingEventsCustomerAddress do
  defstruct [:street, :city]
end

# One event trying to be everything — consumers must guess what changed
defmodule MyApp.Events.ModelingEventsCustomerUpdated do
  use Chronicle.Events.EventType, id: "modeling-events-customer-updated"

  defstruct [:name, :address, :email, :deactivated]
end

# Distinct facts — each consumer subscribes to exactly what it cares about
defmodule MyApp.Events.ModelingEventsCustomerRenamed do
  use Chronicle.Events.EventType, id: "modeling-events-customer-renamed"

  defstruct [:name]
end

defmodule MyApp.Events.ModelingEventsCustomerAddressChanged do
  use Chronicle.Events.EventType, id: "modeling-events-customer-address-changed"

  defstruct [:address]
end

defmodule MyApp.Events.ModelingEventsCustomerDeactivated do
  use Chronicle.Events.EventType, id: "modeling-events-customer-deactivated"

  defstruct [:reason]
end
```
