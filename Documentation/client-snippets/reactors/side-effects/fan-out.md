```elixir
defmodule ReactorSideEffectsFanOutBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-fan-out-book-reserved"

  defstruct [:member_id, :isbn]
end

defmodule ReactorSideEffectsFanOutMemberActivityRecorded do
  use Chronicle.Events.EventType, id: "reactor-side-effects-fan-out-member-activity-recorded"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsFanOutStockDecreased do
  use Chronicle.Events.EventType, id: "reactor-side-effects-fan-out-stock-decreased"

  defstruct [:isbn, :quantity]
end

defmodule ReactorSideEffectsFanOutReservationReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.EventSequences.EventForEventSourceId
  alias ReactorSideEffectsFanOutBookReserved
  alias ReactorSideEffectsFanOutMemberActivityRecorded
  alias ReactorSideEffectsFanOutStockDecreased

  @handles ReactorSideEffectsFanOutBookReserved

  # A reservation ripples to two different event sources — the member gains
  # activity, and the book loses stock. Returning a list of
  # EventForEventSourceId appends them together as one atomic transaction.
  @impl true
  def handle(%ReactorSideEffectsFanOutBookReserved{} = event, _context) do
    {:ok,
     [
       %EventForEventSourceId{
         event_source_id: event.member_id,
         event: %ReactorSideEffectsFanOutMemberActivityRecorded{isbn: event.isbn}
       },
       %EventForEventSourceId{
         event_source_id: event.isbn,
         event: %ReactorSideEffectsFanOutStockDecreased{isbn: event.isbn, quantity: 1}
       }
     ]}
  end
end
```
