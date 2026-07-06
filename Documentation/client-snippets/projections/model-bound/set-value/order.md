```elixir
defmodule MyApp.Events.SetValueOrderPlaced do
  use Chronicle.Events.EventType, id: "set-value-order-placed-v1"

  defstruct [:customer_name]
end

defmodule MyApp.Events.SetValueOrderCanceled do
  use Chronicle.Events.EventType, id: "set-value-order-canceled-v1"

  defstruct []
end

defmodule MyApp.ReadModels.SetValueOrder do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{SetValueOrderPlaced, SetValueOrderCanceled}

  defstruct [:id, :customer_name, :status]

  # A `$value(...)` expression sets a literal constant rather than reading a
  # property off the event.
  from SetValueOrderPlaced,
    set: [id: :event_source_id, customer_name: :customer_name, status: "$value(active)"]

  from SetValueOrderCanceled,
    set: [status: "$value(canceled)"]
end
```
