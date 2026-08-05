```elixir
defmodule MyApp.Events.OrderConfirmationQueued do
  use Chronicle.Events.EventType, id: "order-confirmation-queued"

  defstruct [:customer_id]
end

defmodule MyApp.Reactors.OrderNotifier do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{OrderConfirmationQueued, OrderPlaced}

  @handles OrderPlaced

  @impl true
  def handle(%OrderPlaced{} = event, _context) do
    {:ok, %OrderConfirmationQueued{customer_id: event.customer_id}}
  end
end
```
