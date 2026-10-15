```elixir
defmodule MyApp.Events.DecisionReadsWorkshopOpened do
  use Chronicle.Events.EventType, id: "decision-reads-workshop-opened"

  defstruct [:places]
end

defmodule MyApp.Events.DecisionReadsPlaceBooked do
  use Chronicle.Events.EventType, id: "decision-reads-place-booked"

  defstruct [:attendee]
end

defmodule MyApp.Events.DecisionReadsPlaceCancelled do
  use Chronicle.Events.EventType, id: "decision-reads-place-cancelled"

  defstruct [:attendee]
end

# The decision model: a flat projection keyed by the event source.
defmodule MyApp.ReadModels.DecisionReadsWorkshopPlaces do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, total: 0, booked: 0

  from MyApp.Events.DecisionReadsWorkshopOpened, set: [id: :event_source_id, total: :places]
  from MyApp.Events.DecisionReadsPlaceBooked, add: [booked: 1]
  from MyApp.Events.DecisionReadsPlaceCancelled, subtract: [booked: 1]
end

defmodule MyApp.DecisionReadsBookPlace do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.DecisionReadsPlaceBooked
  alias MyApp.ReadModels.DecisionReadsWorkshopPlaces

  def handle(workshop_id, attendee) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        # 1. The read notes the log position, folds the workshop's events and enrolls
        #    itself as the guard of the unit of work.
        {:ok, read} = DecisionReads.get(DecisionReadsWorkshopPlaces, workshop_id)

        case read.instance do
          %DecisionReadsWorkshopPlaces{total: total, booked: booked} when booked < total ->
            # 2. The append is buffered and committed with the guard. A later booking,
            #    cancellation or opening for this workshop rejects the whole commit.
            :ok = EventLog.append(workshop_id, %DecisionReadsPlaceBooked{attendee: attendee})
            :booked

          _ ->
            :full
        end
      end)

    case result do
      {:ok, :booked} -> true
      {:ok, :full} -> false
      {:error, %DecisionConflict{}} -> false
      {:error, _reason} -> false
    end
  end
end
```
