```elixir title="Count events per type using dictionary increment"
defmodule MyApp.Events.OrderCreated do
  use Chronicle.Events.EventType, id: "order-created-v1"

  defstruct [:order_id, :customer_id]
end

defmodule MyApp.Events.OrderShipped do
  use Chronicle.Events.EventType, id: "order-shipped-v1"

  defstruct [:order_id, :tracking_number]
end

defmodule MyApp.Events.OrderCancelled do
  use Chronicle.Events.EventType, id: "order-cancelled-v1"

  defstruct [:order_id, :reason]
end

defmodule MyApp.ReadModels.CustomerActivity do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{OrderCreated, OrderShipped, OrderCancelled}

  defstruct [:customer_id, :event_counts, :last_activity]

  from OrderCreated,
    set: [
      customer_id: :event_source_id
    ]

  from OrderShipped
  from OrderCancelled

  # Increment a dictionary field keyed by the event type identifier.
  # This creates one counter per distinct event type observed for this customer.
  from_every increment: [event_counts: {:event_context, :type}],
             set: [last_activity: :occurred]
end
```

The `increment: [event_counts: {:event_context, :type}]` declaration:

- `event_counts` is a map field on the read model
- `{:event_context, :type}` tells Chronicle to use the event type identifier as the dictionary key
- Each event increments its type's counter in the `event_counts` map

For this example, Chronicle produces `event_counts` entries such as `"order-created-v1" => 15`,
`"order-shipped-v1" => 12`, and `"order-cancelled-v1" => 3`.

Available event context properties for dictionary keys are `:type` (the event type identifier),
`:correlation_id`, `:causation_id`, and `:caused_by`. `decrement:` works identically to `increment:`,
subtracting instead of adding.
