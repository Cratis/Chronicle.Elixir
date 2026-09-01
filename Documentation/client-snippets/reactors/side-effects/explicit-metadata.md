```elixir
defmodule ReactorSideEffectsExplicitBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-explicit-book-reserved"

  defstruct [:member_id, :isbn]
end

defmodule ReactorSideEffectsExplicitMemberActivityRecorded do
  use Chronicle.Events.EventType, id: "reactor-side-effects-explicit-member-activity-recorded"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsExplicitMetadataReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.EventSequences.EventForEventSourceId
  alias ReactorSideEffectsExplicitBookReserved
  alias ReactorSideEffectsExplicitMemberActivityRecorded

  @handles ReactorSideEffectsExplicitBookReserved

  # An EventForEventSourceId is self-describing: alongside the target event
  # source id it carries the stream type, subject, and every other append
  # option. Set only the fields you need — the rest fall back to defaults.
  @impl true
  def handle(%ReactorSideEffectsExplicitBookReserved{} = event, _context) do
    {:ok,
     %EventForEventSourceId{
       event_source_id: event.member_id,
       event: %ReactorSideEffectsExplicitMemberActivityRecorded{isbn: event.isbn},
       event_stream_type: "members",
       subject: event.member_id
     }}
  end
end
```
