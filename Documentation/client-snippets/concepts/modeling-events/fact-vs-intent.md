```elixir
defmodule MyApp.ModelingEventsAddress do
  defstruct [:street, :city]
end

# A fact that happened
defmodule MyApp.Events.ModelingEventsAddressChanged do
  use Chronicle.Events.EventType, id: "modeling-events-address-changed"

  defstruct [:address]
end

# An intent (that's a command) or a state blob (that's a read model) — not an event
defmodule MyApp.Events.ModelingEventsUpdateAddress do
  use Chronicle.Events.EventType, id: "modeling-events-update-address"

  defstruct [:address]
end
```
