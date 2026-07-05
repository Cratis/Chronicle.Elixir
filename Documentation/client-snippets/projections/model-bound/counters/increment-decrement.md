```elixir
defmodule MyApp.Events.CountersUserConnected do
  use Chronicle.Events.EventType, id: "counters-user-connected-v1"

  defstruct []
end

defmodule MyApp.Events.CountersUserDisconnected do
  use Chronicle.Events.EventType, id: "counters-user-disconnected-v1"

  defstruct []
end

defmodule MyApp.ReadModels.CountersServerStatistics do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{CountersUserConnected, CountersUserDisconnected}

  defstruct [:server_id, active_connections: 0]

  from CountersUserConnected,
    set: [server_id: :event_source_id],
    add: [active_connections: 1]

  from CountersUserDisconnected,
    subtract: [active_connections: 1]
end
```
