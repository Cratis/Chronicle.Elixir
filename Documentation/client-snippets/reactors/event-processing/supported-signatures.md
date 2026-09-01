```elixir
defmodule ReactorSupportedSignaturesOrderPlaced do
  use Chronicle.Events.EventType, id: "reactor-supported-signatures-order-placed"

  defstruct [:order_id]
end

defmodule ReactorSupportedSignaturesReactor do
  use Chronicle.Reactors.Reactor

  alias ReactorSupportedSignaturesOrderPlaced

  @handles ReactorSupportedSignaturesOrderPlaced

  # Every reactor handler has exactly this one shape: the event, then the
  # context map. There is no family of overloads to choose between —
  # dispatch always matches on the event's struct type via @handles.
  @impl true
  def handle(%ReactorSupportedSignaturesOrderPlaced{} = event, context) do
    process(event.order_id, Map.get(context, :occurred))

    :ok
  end

  defp process(_order_id, _occurred), do: :ok
end
```
