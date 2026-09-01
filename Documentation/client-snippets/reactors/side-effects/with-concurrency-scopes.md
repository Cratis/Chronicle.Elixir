```elixir
defmodule ReactorSideEffectsConcurrencyBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-concurrency-book-reserved"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsConcurrencyReservationConfirmed do
  use Chronicle.Events.EventType, id: "reactor-side-effects-concurrency-reservation-confirmed"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsConcurrencyReservationReactor do
  use Chronicle.Reactors.Reactor

  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Events.ConcurrencyScope
  alias ReactorSideEffectsConcurrencyBookReserved
  alias ReactorSideEffectsConcurrencyReservationConfirmed

  @handles ReactorSideEffectsConcurrencyBookReserved

  # Only append if no later event for the triggering source has appeared
  # since this one was read — set concurrency_scope on the
  # EventForEventSourceId to the sequence number the reactor observed.
  @impl true
  def handle(%ReactorSideEffectsConcurrencyBookReserved{} = event, context) do
    {:ok,
     %EventForEventSourceId{
       event_source_id: Map.get(context, :event_source_id),
       event: %ReactorSideEffectsConcurrencyReservationConfirmed{isbn: event.isbn},
       concurrency_scope: ConcurrencyScope.for_event_source(Map.get(context, :sequence_number))
     }}
  end
end
```
