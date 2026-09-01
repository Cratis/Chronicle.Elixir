```elixir
defmodule ReactorSideEffectsMixedBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-mixed-book-reserved"

  defstruct [:member_id, :isbn]
end

defmodule ReactorSideEffectsMixedActivityLogged do
  use Chronicle.Events.EventType, id: "reactor-side-effects-mixed-activity-logged"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsMixedMemberActivityRecorded do
  use Chronicle.Events.EventType, id: "reactor-side-effects-mixed-member-activity-recorded"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsMixedReservationReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.EventSequences.EventForEventSourceId
  alias ReactorSideEffectsMixedBookReserved
  alias ReactorSideEffectsMixedActivityLogged
  alias ReactorSideEffectsMixedMemberActivityRecorded

  @handles ReactorSideEffectsMixedBookReserved

  # A bare event uses the triggering event's own event source id; an
  # EventForEventSourceId keeps its own explicit target. Mixing both in one
  # list still appends them together as a single transaction.
  @impl true
  def handle(%ReactorSideEffectsMixedBookReserved{} = event, _context) do
    {:ok,
     [
       %ReactorSideEffectsMixedActivityLogged{isbn: event.isbn},
       %EventForEventSourceId{
         event_source_id: event.member_id,
         event: %ReactorSideEffectsMixedMemberActivityRecorded{isbn: event.isbn}
       }
     ]}
  end
end
```
