```elixir
defmodule MyApp.Events.ConstantKeyUserRegistered do
  use Chronicle.Events.EventType, id: "constant-key-user-registered-v1"

  defstruct [:name]
end

defmodule MyApp.Events.ConstantKeyOrderPlacedGlobal do
  use Chronicle.Events.EventType, id: "constant-key-order-placed-global-v1"

  defstruct []
end

defmodule MyApp.ReadModels.UserDashboard do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{ConstantKeyUserRegistered, ConstantKeyOrderPlacedGlobal}

  defstruct [:user_id, :name, platform_total_orders: 0]

  # Regular, per-instance key — one document per user.
  from ConstantKeyUserRegistered,
    set: [user_id: :event_source_id, name: :name]

  # A literal key routes this counter to a single shared document instead —
  # "global-stats", not the per-user instance above.
  from ConstantKeyOrderPlacedGlobal,
    key: "$value(global-stats)",
    count: :platform_total_orders
end
```
