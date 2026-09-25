```elixir
defmodule MyApp.Events.EventSequenceLogOrderPlaced do
  use Chronicle.Events.EventType, id: "event-sequence-log-order-placed"

  defstruct order_id: ""
end

defmodule MyApp.Reactors.EventSequenceLocalAuditReactor do
  # Reactors observe the event log by default.
  use Chronicle.Reactors.Reactor

  require Logger
  alias MyApp.Events.EventSequenceLogOrderPlaced

  @handles EventSequenceLogOrderPlaced

  @impl true
  def handle(%EventSequenceLogOrderPlaced{order_id: order_id}, context) do
    Logger.info("Order #{order_id} placed at #{Map.get(context, :occurred)}")
    :ok
  end
end
```
