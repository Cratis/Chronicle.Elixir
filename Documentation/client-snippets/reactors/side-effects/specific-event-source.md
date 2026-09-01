```elixir
defmodule ReactorSideEffectsSpecificBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-specific-book-reserved"

  defstruct [:member_id, :isbn]
end

defmodule ReactorSideEffectsSpecificMemberActivityRecorded do
  use Chronicle.Events.EventType, id: "reactor-side-effects-specific-member-activity-recorded"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsSpecificReservationReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.EventSequences.EventForEventSourceId
  alias ReactorSideEffectsSpecificBookReserved
  alias ReactorSideEffectsSpecificMemberActivityRecorded

  @handles ReactorSideEffectsSpecificBookReserved

  # MemberActivityRecorded is a fact about the member, not the book that
  # triggered the reactor — pick the target event source id explicitly by
  # returning an EventForEventSourceId instead of a bare event.
  @impl true
  def handle(%ReactorSideEffectsSpecificBookReserved{} = event, _context) do
    {:ok,
     %EventForEventSourceId{
       event_source_id: event.member_id,
       event: %ReactorSideEffectsSpecificMemberActivityRecorded{isbn: event.isbn}
     }}
  end
end
```
