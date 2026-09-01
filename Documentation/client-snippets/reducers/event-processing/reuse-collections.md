```elixir
defmodule EventProcessingReuseItemAdded do
  use Chronicle.Events.EventType, id: "event-processing-reuse-item-added"

  defstruct [:item_id, :name]
end

defmodule EventProcessingItem do
  defstruct [:item_id, :name]
end

defmodule EventProcessingItemList do
  defstruct items: []
end

defmodule EventProcessingItemListReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingItemList

  alias EventProcessingReuseItemAdded
  alias EventProcessingItem

  @handles EventProcessingReuseItemAdded

  # Elixir lists are immutable, so `++` always returns a new list rather than
  # mutating a shared one — there is no in-place mutation hazard here.
  @impl true
  def reduce(%EventProcessingReuseItemAdded{} = event, current, _context) do
    items = if current, do: current.items, else: []
    item = %EventProcessingItem{item_id: event.item_id, name: event.name}

    %EventProcessingItemList{items: items ++ [item]}
  end
end
```
