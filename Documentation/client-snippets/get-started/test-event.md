```elixir title="The event - an immutable fact"
defmodule MyApp.Events.TestEvent do
  use Chronicle.Events.EventType, id: "test-event-v1"

  defstruct [:message]
end
```
