```elixir
defmodule MyApp.Events.RepairReactorConcertAnnounced do
  use Chronicle.Events.EventType, id: "repair-reactor-concert-announced"

  defstruct [:name, :capacity]
end

defmodule MyApp.Events.RepairReactorSeatReserved do
  use Chronicle.Events.EventType, id: "repair-reactor-seat-reserved"

  defstruct [:reserved_by]
end

defmodule MyApp.Events.RepairReactorConcertOverbooked do
  use Chronicle.Events.EventType, id: "repair-reactor-concert-overbooked"

  defstruct [:excess]
end

defmodule MyApp.ReadModels.RepairReactorConcertSeats do
  use Chronicle.ReadModels.ReadModel, passive: true

  defstruct id: nil, capacity: 0, reserved: 0

  from MyApp.Events.RepairReactorConcertAnnounced, set: [id: :event_source_id, capacity: :capacity]
  from MyApp.Events.RepairReactorSeatReserved, count: :reserved
end

defmodule MyApp.Reactors.RepairReactorOverbookingRepair do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{RepairReactorConcertOverbooked, RepairReactorSeatReserved}
  alias MyApp.ReadModels.RepairReactorConcertSeats

  @handles RepairReactorSeatReserved

  # A passive read model is folded when it is read, so it includes the reservation that triggered this call.
  @impl true
  def handle(%RepairReactorSeatReserved{}, context) do
    {:ok, seats} = Chronicle.read_model(RepairReactorConcertSeats, context.event_source_id)

    case seats do
      %RepairReactorConcertSeats{reserved: reserved, capacity: capacity} when reserved > capacity ->
        {:ok, %RepairReactorConcertOverbooked{excess: reserved - capacity}}

      _ ->
        :ok
    end
  end
end
```
