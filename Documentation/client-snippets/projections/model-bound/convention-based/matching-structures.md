```elixir title="Matching nested structures and collections"
defmodule MyApp.Events.ConventionCustomerRegistered do
  use Chronicle.Events.EventType, id: "convention-customer-registered-v1"

  defstruct [:first_name, :last_name, :billing_address, :shipping_address]
end

defmodule MyApp.Events.ConventionOrderCreated do
  use Chronicle.Events.EventType, id: "convention-order-created-v1"

  defstruct [:customer_email, :items, :tags]
end

defmodule MyApp.ReadModels.ConventionCustomer do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ConventionCustomerRegistered

  # Nested maps and lists are plain Elixir terms — matching field names on the
  # event are copied across as-is, structure and all.
  defstruct [:first_name, :last_name, :billing_address, :shipping_address]

  from ConventionCustomerRegistered
end

defmodule MyApp.ReadModels.ConventionOrder do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ConventionOrderCreated

  defstruct [:customer_email, :items, :tags]

  from ConventionOrderCreated
end
```
