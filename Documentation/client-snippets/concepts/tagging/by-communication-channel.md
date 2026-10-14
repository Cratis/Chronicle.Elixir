```elixir
defmodule MyApp.Events.TaggingByCommunicationChannelExample do
  use Chronicle.Events.EventType,
    id: "tagging-by-communication-channel-example",
    tags: ["Email", "SMS", "Push", "Webhook"]

  defstruct [:data]
end
```
