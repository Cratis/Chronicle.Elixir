```elixir
defmodule MyApp.CorrelationIdentityCausationCausation do
  alias Chronicle.Auditing.CausationManager

  def record_place_order(order_id) do
    CausationManager.add("MyApp.Commands.PlaceOrder", %{order_id: order_id})
  end
end
```
