```elixir
defmodule MyApp.Events.TestingCollectionFirstItemAdded do
  use Cratis.Chronicle.Events.EventType, id: "testing-collection-first-item-added"

  defstruct [:name]
end

defmodule MyApp.Events.TestingCollectionSecondItemAdded do
  use Cratis.Chronicle.Events.EventType, id: "testing-collection-second-item-added"

  defstruct [:name]
end

defmodule MyApp.TestingCollectionMultipleEventsTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingCollectionFirstItemAdded,
      MyApp.Events.TestingCollectionSecondItemAdded
    ]

  alias MyApp.Events.{TestingCollectionFirstItemAdded, TestingCollectionSecondItemAdded}

  test "locating the second of several captured events", %{chronicle: client} do
    event_source_id = "item-#{System.unique_integer([:positive])}"

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        event_source_id,
        %TestingCollectionFirstItemAdded{name: "Widget"},
        client: client
      )

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        event_source_id,
        %TestingCollectionSecondItemAdded{name: "Gadget"},
        client: client
      )

    second_event =
      client
      |> Cratis.Chronicle.Testing.appended_events(event_source_id)
      |> Enum.map(& &1.event)
      |> Enum.find(&match?(%TestingCollectionSecondItemAdded{}, &1))

    assert %TestingCollectionSecondItemAdded{name: "Gadget"} = second_event
  end
end
```
