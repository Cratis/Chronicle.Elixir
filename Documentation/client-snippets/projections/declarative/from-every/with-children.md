```elixir title="Include child events in from_every"
defmodule MyApp.Events.OrderCreatedDeclarativeEveryWithChildren do
  use Chronicle.Events.EventType, id: "order-created-declarative-every-with-children-v1"

  defstruct [:order_number]
end

defmodule MyApp.Events.OrderLineAddedDeclarativeEveryWithChildren do
  use Chronicle.Events.EventType, id: "order-line-added-declarative-every-with-children-v1"

  defstruct [:line_id, :product_name]
end

defmodule MyApp.ReadModels.OrderLineDeclarativeEveryWithChildren do
  defstruct line_id: nil, product_name: nil
end

defmodule MyApp.ReadModels.OrderDeclarativeEveryWithChildren do
  use Chronicle.ReadModels.ReadModel,
    types: [lines: {:list, MyApp.ReadModels.OrderLineDeclarativeEveryWithChildren}]

  defstruct [:order_number, :last_updated, lines: []]
end

defmodule MyApp.Projections.OrderDeclarativeEveryWithChildrenProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.OrderDeclarativeEveryWithChildren

  alias MyApp.Events.{
    OrderCreatedDeclarativeEveryWithChildren,
    OrderLineAddedDeclarativeEveryWithChildren
  }

  from OrderCreatedDeclarativeEveryWithChildren

  children :lines, identified_by: :line_id do
    from OrderLineAddedDeclarativeEveryWithChildren,
      key: :line_id,
      set: [line_id: :line_id, product_name: :product_name]
  end

  # include_children: true touches the containing parent's own from_every mappings whenever a
  # child-only event occurs too, not just the order's own events.
  from_every set: [last_updated: :occurred], include_children: true
end
```
