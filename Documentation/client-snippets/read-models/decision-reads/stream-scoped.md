```elixir
defmodule MyApp.Events.StreamOrderPlaced do
  use Chronicle.Events.EventType, id: "stream-order-placed"

  defstruct [:status]
end

defmodule MyApp.ReadModels.StreamOrderEligibility do
  use Chronicle.ReadModels.ReadModel, passive: true

  defstruct id: nil, status: nil

  from MyApp.Events.StreamOrderPlaced, set: [id: :event_source_id, status: :status]
end

defmodule MyApp.StreamDecisionExample do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.DecisionReads
  alias MyApp.Events.StreamOrderPlaced
  alias MyApp.ReadModels.StreamOrderEligibility

  def place_order(order_id) do
    Chronicle.decide(fn _unit_of_work ->
      # Folds and guards only the "orders" / "checkout" stream of this event source.
      {:ok, read} = DecisionReads.get(StreamOrderEligibility, order_id, "orders", "checkout")

      # Make the decision using read.instance, including the absent case.
      if read.instance == nil do
        EventLog.append(order_id, %StreamOrderPlaced{status: "placed"},
          event_stream_type: "orders",
          event_stream_id: "checkout"
        )
      end
    end)
  end
end
```
