```elixir
defmodule EventProcessingSkipItemAdded do
  use Chronicle.Events.EventType, id: "event-processing-skip-item-added"

  defstruct [:price]
end

defmodule EventProcessingSkipOrderSummary do
  defstruct total: 0
end

defmodule EventProcessingSkipOrderSummaryReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingSkipOrderSummary

  alias EventProcessingSkipItemAdded

  @handles EventProcessingSkipItemAdded

  # Can't add items if the order doesn't exist yet — returning nil when
  # current is already nil is a no-op.
  @impl true
  def reduce(%EventProcessingSkipItemAdded{}, nil, _context), do: nil

  def reduce(%EventProcessingSkipItemAdded{} = event, current, _context) do
    %{current | total: current.total + event.price}
  end
end
```
