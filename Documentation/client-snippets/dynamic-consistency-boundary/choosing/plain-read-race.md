```elixir
defmodule MyApp.Events.PlainReadRaceSeatOpened do
  use Chronicle.Events.EventType, id: "plain-read-race-seat-opened"

  defstruct [:row]
end

defmodule MyApp.Events.PlainReadRaceSeatClaimed do
  use Chronicle.Events.EventType, id: "plain-read-race-seat-claimed"

  defstruct [:claimed_by]
end

defmodule MyApp.ReadModels.PlainReadRaceSeatAvailability do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, claims: 0

  from MyApp.Events.PlainReadRaceSeatOpened, set: [id: :event_source_id]
  from MyApp.Events.PlainReadRaceSeatClaimed, count: :claims
end

defmodule MyApp.ClaimSeatWithAPlainRead do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.PlainReadRaceSeatClaimed

  # Do not use this to make a rule hold. Two requests can both read claims = 0
  # and both append. The read guards nothing.
  def claim(seat_id, claimed_by) do
    {:ok, seat} = Chronicle.read_model(MyApp.ReadModels.PlainReadRaceSeatAvailability, seat_id)

    if seat != nil and seat.claims > 0 do
      false
    else
      EventLog.append(seat_id, %PlainReadRaceSeatClaimed{claimed_by: claimed_by}) == :ok
    end
  end
end
```
