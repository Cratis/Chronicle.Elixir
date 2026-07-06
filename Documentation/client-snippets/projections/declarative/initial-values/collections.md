```elixir title="Initialize collections"
defmodule MyApp.Events.InitialValuesCustomerRegistered do
  use Chronicle.Events.EventType, id: "initial-values-customer-registered"

  defstruct [:name]
end

defmodule MyApp.ReadModels.InitialValuesCustomerRecord do
  use Chronicle.ReadModels.ReadModel

  defstruct name: "", addresses: [], tags: []
end

defmodule MyApp.Projections.InitialValuesCustomerRecordProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.InitialValuesCustomerRecord

  alias MyApp.Events.InitialValuesCustomerRegistered

  from InitialValuesCustomerRegistered
end
```
