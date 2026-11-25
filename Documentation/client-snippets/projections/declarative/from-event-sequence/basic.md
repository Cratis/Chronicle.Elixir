```elixir
defmodule MyApp.Events.FromEventSequenceOrderCreated do
  use Cratis.Chronicle.Events.EventType, id: "from-event-sequence-order-created"

  defstruct [:customer]
end

defmodule MyApp.ReadModels.FromEventSequenceOrder do
  use Cratis.Chronicle.ReadModels.ReadModel, event_sequence: "order-management"

  defstruct id: nil, customer: nil

  from MyApp.Events.FromEventSequenceOrderCreated,
    set: [id: :event_source_id, customer: :customer]
end
```
