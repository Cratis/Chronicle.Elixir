```elixir title="Read a shared event property from every event"
defmodule MyApp.Events.OrderConfirmedForEvery do
  use Cratis.Chronicle.Events.EventType, id: "order-confirmed-for-every-v1"

  defstruct [:status]
end

defmodule MyApp.Events.OrderShippedForEvery do
  use Cratis.Chronicle.Events.EventType, id: "order-shipped-for-every-v1"

  defstruct [:status]
end

defmodule MyApp.ReadModels.OrderStatusFromEvery do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{OrderConfirmedForEvery, OrderShippedForEvery}

  defstruct [:id, :current_status]

  from OrderConfirmedForEvery,
    set: [id: :event_source_id]

  from OrderShippedForEvery

  from_every set: [current_status: :status]
end
```
