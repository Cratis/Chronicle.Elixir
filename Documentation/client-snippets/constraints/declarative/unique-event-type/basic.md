```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeProjectInitialized do
  use Cratis.Chronicle.Events.EventType, id: "constraints-unique-event-type-project-initialized"

  unique_event_type()

  defstruct []
end
```
