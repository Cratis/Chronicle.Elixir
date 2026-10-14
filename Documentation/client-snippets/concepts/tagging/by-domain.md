```elixir
defmodule MyApp.Events.TaggingByDomainExample do
  use Chronicle.Events.EventType,
    id: "tagging-by-domain-example",
    tags: ["Sales", "Inventory", "Customer", "Shipping"]

  defstruct [:data]
end
```
