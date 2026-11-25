```elixir
defmodule MyApp.Events.TaggingByStakeholderExample do
  use Cratis.Chronicle.Events.EventType,
    id: "tagging-by-stakeholder-example",
    tags: ["Customer", "Operations", "Finance", "Support", "Executive"]

  defstruct [:data]
end
```
