```elixir
defmodule MyApp.Events.TaggingByIntegrationTypeExample do
  use Chronicle.Events.EventType,
    id: "tagging-by-integration-type-example",
    tags: ["Notifications", "ExternalAPI", "MessageQueue", "FileSystem"]

  defstruct [:data]
end
```
