```elixir
defmodule EventProcessingContextOrderPlaced do
  use Chronicle.Events.EventType, id: "event-processing-context-order-placed"

  defstruct [:order_id, :amount]
end

defmodule EventProcessingOrderSummaryWithContext do
  defstruct [:order_id, :total, :placed_at, :sequence_number]
end

defmodule EventProcessingOrderSummaryWithContextReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingOrderSummaryWithContext

  alias EventProcessingContextOrderPlaced

  @handles EventProcessingContextOrderPlaced

  @impl true
  def reduce(%EventProcessingContextOrderPlaced{} = event, _current, context) do
    %EventProcessingOrderSummaryWithContext{
      order_id: event.order_id,
      total: event.amount,
      placed_at: Map.get(context, :occurred),
      sequence_number: Map.get(context, :sequence_number)
    }
  end
end
```
