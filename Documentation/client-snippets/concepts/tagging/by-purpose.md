```elixir
defmodule MyApp.Events.TaggingByPurposeExample do
  use Cratis.Chronicle.Events.EventType,
    id: "tagging-by-purpose-example",
    tags: ["Analytics", "Reporting", "Integration", "Alerting", "Monitoring", "Automation"]

  defstruct [:data]
end
```
