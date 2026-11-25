```elixir title="Map event context"
defmodule MyApp.Events.OrderPlacedForAudit do
  use Cratis.Chronicle.Events.EventType, id: "order-placed-for-audit-v1"

  defstruct [:customer_name]
end

defmodule MyApp.ReadModels.AuditedOrder do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.OrderPlacedForAudit

  defstruct [:id, :customer_name, :ordered_at]

  from OrderPlacedForAudit,
    set: [
      id: :event_source_id,
      customer_name: :customer_name,
      ordered_at: :occurred
    ]
end
```
