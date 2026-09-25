```elixir
defmodule MyApp.Events.MbEventSeqFluentOrderPlaced do
  use Chronicle.Events.EventType, id: "mb-event-seq-fluent-order-placed"

  defstruct amount: 0.0
end

defmodule MyApp.ReadModels.MbEventSeqFluentOrderSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct total_amount: 0.0
end

defmodule MyApp.Projections.MbEventSeqFluentOrderProjection do
  use Chronicle.Projections.Projection,
    model: MyApp.ReadModels.MbEventSeqFluentOrderSummary,
    event_sequence: "custom-sequence"

  from MyApp.Events.MbEventSeqFluentOrderPlaced,
    set: [total_amount: :amount]
end
```
