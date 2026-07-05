```elixir
defmodule MyApp.EmailGateway do
  def order_placed(_email, _amount, _occurred), do: :ok
end

defmodule MyApp.Reactors.OrderNotificationsReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ReactorOrderPlaced

  @handles ReactorOrderPlaced

  @impl true
  def handle(%ReactorOrderPlaced{} = event, context) do
    MyApp.EmailGateway.order_placed(
      event.customer_email,
      event.total_amount,
      Map.get(context, :occurred))

    :ok
  end
end
```
