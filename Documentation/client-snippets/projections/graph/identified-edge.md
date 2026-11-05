```elixir
defmodule MyApp.Events.CustomerRegistered do
  use Chronicle.Events.EventType, id: "graph-customer-registered"
  defstruct customer_id: ""
end

defmodule MyApp.Events.ShopRegistered do
  use Chronicle.Events.EventType, id: "graph-shop-registered"
  defstruct shop_id: ""
end

defmodule MyApp.Events.ShopVisited do
  use Chronicle.Events.EventType, id: "graph-shop-visited"
  defstruct customer_id: "", shop_id: "", visit_id: ""
end

defmodule MyApp.Graphs.Customer do
  use Chronicle.Graphs.Node
  defstruct customer_id: ""
end

defmodule MyApp.Graphs.Shop do
  use Chronicle.Graphs.Node
  defstruct shop_id: ""
end

defmodule MyApp.Graphs.Visited do
  use Chronicle.Graphs.Edge, type: "VISITED"
  defstruct visit_id: "", times: 0
end

defmodule MyApp.Graphs.Visits do
  use Chronicle.Graphs.Graph, id: "Visits"

  alias MyApp.Events.{CustomerRegistered, ShopRegistered, ShopVisited}
  alias MyApp.Graphs.{Customer, Shop, Visited}

  node Customer, key: :customer_id do
    from CustomerRegistered, key: :customer_id
  end

  node Shop, key: :shop_id do
    from ShopRegistered, key: :shop_id
  end

  # The visit identifies the edge, so a customer can have several VISITED edges to one shop.
  # Every event of the edge reads the visit from the event property of the same name, or from
  # the property `identity:` names.
  edge Visited, source: Customer, target: Shop, identified_by: :visit_id do
    from ShopVisited, source_key: :customer_id, target_key: :shop_id, count: :times
  end
end
```
