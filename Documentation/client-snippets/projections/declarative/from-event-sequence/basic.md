```elixir
defmodule MyApp.Events.FromEventSequenceOrderCreated do
  use Chronicle.Events.EventType, id: "from-event-sequence-order-created"

  defstruct [:customer]
end

defmodule MyApp.ReadModels.FromEventSequenceOrder do
  use Chronicle.ReadModels.ReadModel, event_sequence: "order-management"

  defstruct id: nil, customer: nil

  from MyApp.Events.FromEventSequenceOrderCreated,
    set: [id: :event_source_id, customer: :customer]
end
```
