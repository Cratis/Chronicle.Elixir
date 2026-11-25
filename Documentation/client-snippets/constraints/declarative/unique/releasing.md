```elixir
defmodule MyApp.Events.ConstraintsUniqueOrderPlaced do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-order-placed"

  unique :reference, name: "ConstraintsUniqueOrderReference"

  defstruct reference: ""
end

defmodule MyApp.Events.ConstraintsUniqueOrderCancelled do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-order-cancelled"

  remove_constraint "ConstraintsUniqueOrderReference"

  defstruct []
end
```
