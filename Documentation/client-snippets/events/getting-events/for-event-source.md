```elixir
defmodule MyApp.Events.GettingEventsOrderPlaced do
  use Cratis.Chronicle.Events.EventType, id: "getting-events-order-placed"

  defstruct [:order_id, :total]
end

defmodule MyApp.Events.GettingEventsOrderCancelled do
  use Cratis.Chronicle.Events.EventType, id: "getting-events-order-cancelled"

  defstruct [:order_id, :reason]
end

defmodule MyApp.GettingEventsOrderHistoryReader do
  alias Cratis.Chronicle.EventSequences.EventLog
  alias MyApp.Events.{GettingEventsOrderCancelled, GettingEventsOrderPlaced}

  def get_order_events(order_id) do
    # Filters the timeline to only the order events you care about.
    EventLog.get_for_event_source(order_id,
      event_types: [GettingEventsOrderPlaced, GettingEventsOrderCancelled]
    )
  end
end
```
