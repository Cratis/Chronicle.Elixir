```elixir
defmodule EventProcessingOrderCreated do
  use Chronicle.Events.EventType, id: "event-processing-order-created"

  defstruct [:order_id]
end

defmodule EventProcessingItemAdded do
  use Chronicle.Events.EventType, id: "event-processing-item-added"

  defstruct [:price]
end

defmodule EventProcessingOrderSummary do
  defstruct [:order_id, :total, :last_updated]
end

defmodule EventProcessingOrderSummaryReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingOrderSummary

  alias EventProcessingOrderCreated
  alias EventProcessingItemAdded

  @handles EventProcessingOrderCreated
  @handles EventProcessingItemAdded

  # Dispatch matches on the event struct's type, not a method name —
  # Chronicle picks the reduce/3 clause whose first-argument pattern matches
  # the incoming event.
  @impl true
  def reduce(%EventProcessingOrderCreated{} = event, _current, context) do
    %EventProcessingOrderSummary{
      order_id: event.order_id,
      total: 0,
      last_updated: Map.get(context, :occurred)
    }
  end

  # Skip if no order exists yet
  def reduce(%EventProcessingItemAdded{}, nil, _context), do: nil

  def reduce(%EventProcessingItemAdded{} = event, current, context) do
    %{
      current
      | total: current.total + event.price,
        last_updated: Map.get(context, :occurred)
    }
  end
end
```
