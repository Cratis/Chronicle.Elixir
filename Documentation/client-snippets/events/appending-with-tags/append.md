```elixir
defmodule MyApp.Events.TaggedOrderPlaced do
  defstruct [:customer_id, :total]
end

defmodule MyApp.TaggedCheckoutService do
  alias MyApp.Events.TaggedOrderPlaced

  def place_order(order_id, customer_id, total) do
    Chronicle.append(
      order_id,
      %TaggedOrderPlaced{customer_id: customer_id, total: total},
      tags: ["checkout", "priority"]
    )
  end
end
```
