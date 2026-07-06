```elixir
defmodule MyApp.Events.ReducersGettingStartedOrderCreated do
  use Chronicle.Events.EventType, id: "reducers-getting-started-order-created"

  defstruct [:order_id]
end

defmodule MyApp.Events.ReducersGettingStartedItemAddedToOrder do
  use Chronicle.Events.EventType, id: "reducers-getting-started-item-added-to-order"

  defstruct [:price, :quantity]
end

defmodule MyApp.Events.ReducersGettingStartedItemRemovedFromOrder do
  use Chronicle.Events.EventType, id: "reducers-getting-started-item-removed-from-order"

  defstruct [:price, :quantity]
end

defmodule MyApp.Reducers.ReducersGettingStartedOrderSummaryReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.ReducersGettingStartedOrderSummary

  alias MyApp.Events.{
    ReducersGettingStartedItemAddedToOrder,
    ReducersGettingStartedItemRemovedFromOrder,
    ReducersGettingStartedOrderCreated
  }

  @handles ReducersGettingStartedOrderCreated
  @handles ReducersGettingStartedItemAddedToOrder
  @handles ReducersGettingStartedItemRemovedFromOrder

  @impl true
  def reduce(%ReducersGettingStartedOrderCreated{} = event, _model, context) do
    %MyApp.ReadModels.ReducersGettingStartedOrderSummary{
      order_id: event.order_id,
      total_amount: 0,
      item_count: 0,
      last_updated: Map.get(context, :occurred)
    }
  end

  # Skip if order not created yet
  def reduce(%ReducersGettingStartedItemAddedToOrder{}, nil, _context), do: nil

  def reduce(%ReducersGettingStartedItemAddedToOrder{} = event, model, context) do
    %{
      model
      | total_amount: model.total_amount + event.price * event.quantity,
        item_count: model.item_count + event.quantity,
        last_updated: Map.get(context, :occurred)
    }
  end

  # Skip if order not created yet
  def reduce(%ReducersGettingStartedItemRemovedFromOrder{}, nil, _context), do: nil

  def reduce(%ReducersGettingStartedItemRemovedFromOrder{} = event, model, context) do
    %{
      model
      | total_amount: model.total_amount - event.price * event.quantity,
        item_count: model.item_count - event.quantity,
        last_updated: Map.get(context, :occurred)
    }
  end
end
```
