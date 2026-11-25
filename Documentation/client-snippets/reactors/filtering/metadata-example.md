```elixir
defmodule ReactorsFilteringOrderPlaced do
  use Cratis.Chronicle.Events.EventType, id: "reactors-filtering-order-placed"

  defstruct [:total_amount]
end

defmodule ReactorsFilteringMetadataExampleService do
  alias ReactorsFilteringOrderPlaced

  def place_order(order_id, total_amount) do
    Cratis.Chronicle.append(
      order_id,
      %ReactorsFilteringOrderPlaced{total_amount: total_amount},
      tags: ["priority"],
      event_source_type: "order",
      event_stream_type: "fulfillment"
    )
  end
end
```
