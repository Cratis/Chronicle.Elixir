```elixir
defmodule MyApp.Events.TaggingByPurposeExample do
  use Chronicle.Events.EventType,
    id: "tagging-by-purpose-example",
    tags: ["Analytics", "Reporting", "Integration", "Alerting", "Monitoring", "Automation"]

  defstruct [:data]
end
```
