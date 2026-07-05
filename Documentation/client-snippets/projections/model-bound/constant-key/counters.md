```elixir
defmodule MyApp.Events.ConstantKeyOrderPlacedForMetrics do
  use Chronicle.Events.EventType, id: "constant-key-order-placed-for-metrics-v1"

  defstruct []
end

defmodule MyApp.Events.ConstantKeyUserLoggedIn do
  use Chronicle.Events.EventType, id: "constant-key-user-logged-in-v1"

  defstruct []
end

defmodule MyApp.Events.ConstantKeyUserLoggedOut do
  use Chronicle.Events.EventType, id: "constant-key-user-logged-out-v1"

  defstruct []
end

defmodule MyApp.Events.ConstantKeyErrorOccurred do
  use Chronicle.Events.EventType, id: "constant-key-error-occurred-v1"

  defstruct []
end

defmodule MyApp.ReadModels.SystemMetrics do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    ConstantKeyOrderPlacedForMetrics,
    ConstantKeyUserLoggedIn,
    ConstantKeyUserLoggedOut,
    ConstantKeyErrorOccurred
  }

  defstruct total_orders: 0, active_sessions: 0, total_errors: 0

  from ConstantKeyOrderPlacedForMetrics,
    key: "$value(metrics)",
    count: :total_orders

  from ConstantKeyUserLoggedIn,
    key: "$value(metrics)",
    add: [active_sessions: 1]

  from ConstantKeyUserLoggedOut,
    key: "$value(metrics)",
    subtract: [active_sessions: 1]

  from ConstantKeyErrorOccurred,
    key: "$value(metrics)",
    count: :total_errors
end
```
