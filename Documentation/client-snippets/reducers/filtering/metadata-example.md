```elixir
defmodule ReducersFilteringOrderPlaced do
  use Chronicle.Events.EventType, id: "reducers-filtering-order-placed"

  defstruct [:total_amount]
end

defmodule ReducersFilteringMetadataExampleService do
  alias ReducersFilteringOrderPlaced

  def place_order(order_id, total_amount) do
    Chronicle.append(
      order_id,
      %ReducersFilteringOrderPlaced{total_amount: total_amount},
      tags: ["priority"],
      event_source_type: "order",
      event_stream_type: "fulfillment"
    )
  end
end
```
