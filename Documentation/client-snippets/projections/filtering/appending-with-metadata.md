```elixir
defmodule MyApp.Events.FilteringMetadataOrderPlaced do
  use Chronicle.Events.EventType, id: "filtering-metadata-order-placed"

  defstruct [:customer_id, :total_amount]
end

defmodule MyApp.FilteringAppendService do
  alias MyApp.Events.FilteringMetadataOrderPlaced

  def append_orders(order_id, customer_id) do
    # Appends to all observers — no extra metadata
    Chronicle.append(order_id, %FilteringMetadataOrderPlaced{customer_id: customer_id, total_amount: 42})

    # Appends to all observers; additionally dispatched to observers filtering on "premium"
    Chronicle.append(
      order_id,
      %FilteringMetadataOrderPlaced{customer_id: customer_id, total_amount: 299},
      tags: ["premium"]
    )

    # Appends with stream type; dispatched to observers filtering on "wholesale" stream type
    Chronicle.append(
      order_id,
      %FilteringMetadataOrderPlaced{customer_id: customer_id, total_amount: 1500},
      event_stream_type: "wholesale"
    )
  end
end
```
