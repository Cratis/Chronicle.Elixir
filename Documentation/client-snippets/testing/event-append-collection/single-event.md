```elixir
defmodule MyApp.Events.TestingCollectionSingleItemRegistered do
  use Cratis.Chronicle.Events.EventType, id: "testing-collection-single-item-registered"

  defstruct [:name]
end

defmodule MyApp.TestingCollectionSingleEventTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingCollectionSingleItemRegistered]

  alias MyApp.Events.TestingCollectionSingleItemRegistered

  test "exactly one event is captured", %{chronicle: client} do
    event_source_id = "item-#{System.unique_integer([:positive])}"

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        event_source_id,
        %TestingCollectionSingleItemRegistered{name: "Widget"},
        client: client
      )

    captured = Cratis.Chronicle.Testing.appended_events(client, event_source_id)

    assert [%{event: %TestingCollectionSingleItemRegistered{}, context: context}] = captured
    assert context.sequence_number != nil
  end
end
```
