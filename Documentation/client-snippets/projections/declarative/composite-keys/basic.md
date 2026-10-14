```elixir title="Composite key projection"
defmodule MyApp.Projections.CompositeOrderProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.CompositeOrder

  alias MyApp.Events.{CompositeOrderCreated, CompositeOrderShipped}

  from CompositeOrderCreated,
    key: {:composite, [customer_id: :customer_id, order_number: :order_number]}

  from CompositeOrderShipped,
    key: {:composite, [customer_id: :customer_id, order_number: :order_number]}
end
```
