```elixir
defmodule EventProcessingOrderCreatedForStatus do
  use Chronicle.Events.EventType, id: "event-processing-order-created-for-status"

  defstruct [:order_id]
end

defmodule EventProcessingOrderPaid do
  use Chronicle.Events.EventType, id: "event-processing-order-paid"

  defstruct [:order_id]
end

defmodule EventProcessingOrderShipped do
  use Chronicle.Events.EventType, id: "event-processing-order-shipped"

  defstruct [:order_id]
end

defmodule EventProcessingOrderDelivered do
  use Chronicle.Events.EventType, id: "event-processing-order-delivered"

  defstruct [:order_id]
end

defmodule EventProcessingOrderCancelled do
  use Chronicle.Events.EventType, id: "event-processing-order-cancelled"

  defstruct [:order_id]
end

defmodule EventProcessingOrderStatus do
  defstruct [:state, :last_updated]
end

defmodule EventProcessingOrderStatusReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingOrderStatus

  alias EventProcessingOrderCreatedForStatus
  alias EventProcessingOrderPaid
  alias EventProcessingOrderShipped
  alias EventProcessingOrderDelivered
  alias EventProcessingOrderCancelled

  @handles EventProcessingOrderCreatedForStatus
  @handles EventProcessingOrderPaid
  @handles EventProcessingOrderShipped
  @handles EventProcessingOrderDelivered
  @handles EventProcessingOrderCancelled

  @impl true
  def reduce(%EventProcessingOrderCreatedForStatus{}, _current, context),
    do: %EventProcessingOrderStatus{state: "created", last_updated: Map.get(context, :occurred)}

  def reduce(%EventProcessingOrderPaid{}, _current, context),
    do: %EventProcessingOrderStatus{state: "paid", last_updated: Map.get(context, :occurred)}

  def reduce(%EventProcessingOrderShipped{}, _current, context),
    do: %EventProcessingOrderStatus{state: "shipped", last_updated: Map.get(context, :occurred)}

  def reduce(%EventProcessingOrderDelivered{}, _current, context),
    do: %EventProcessingOrderStatus{state: "delivered", last_updated: Map.get(context, :occurred)}

  def reduce(%EventProcessingOrderCancelled{}, _current, context),
    do: %EventProcessingOrderStatus{state: "cancelled", last_updated: Map.get(context, :occurred)}
end
```
