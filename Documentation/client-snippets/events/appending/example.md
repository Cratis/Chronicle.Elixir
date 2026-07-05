```elixir
defmodule MyApp.Events.OrderPlaced do
  use Chronicle.Events.EventType, id: "order-placed"

  defstruct [:customer_id, :total]
end

defmodule MyApp.CheckoutService do
  def place_order(order_id, customer_id, total) do
    case Chronicle.append(order_id, %MyApp.Events.OrderPlaced{
           customer_id: customer_id,
           total: total
         }) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        # Decide whether to retry or surface a conflict to the caller.
        error
    end
  end
end
```
