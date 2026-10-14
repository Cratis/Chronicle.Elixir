```elixir
defmodule MyApp.TestingCollectionViolationSpecTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingCollectionUniqueValueRecorded,
      MyApp.Events.TestingCollectionUniqueValueFollowUp
    ],
    reactors: [MyApp.Reactors.TestingCollectionUniqueValueReactor]

  alias MyApp.Events.{TestingCollectionUniqueValueFollowUp, TestingCollectionUniqueValueRecorded}

  test "a reactor's duplicate follow-up append is rejected by the constraint", %{chronicle: client} do
    unique_value = "value-#{System.unique_integer([:positive])}"
    first_event_source_id = "value-#{System.unique_integer([:positive])}-a"
    second_event_source_id = "value-#{System.unique_integer([:positive])}-b"

    :ok =
      Chronicle.EventSequences.EventLog.append(
        first_event_source_id,
        %TestingCollectionUniqueValueRecorded{unique_value: unique_value},
        client: client
      )

    :ok =
      Chronicle.EventSequences.EventLog.append(
        second_event_source_id,
        %TestingCollectionUniqueValueRecorded{unique_value: unique_value},
        client: client
      )

    # An append the kernel rejects is never committed, so it is never in
    # `appended_events/2` — the rejection surfaces through `wait_for_observers/1`
    # instead, as a reactor failure.
    assert {:error, [{:reactor, MyApp.Reactors.TestingCollectionUniqueValueReactor, reason}]} =
             Chronicle.Testing.wait_for_observers(client)

    assert {:constraint_violations, _violations} = reason

    assert [%TestingCollectionUniqueValueFollowUp{unique_value: ^unique_value}] =
             first_event_source_id
             |> then(&Chronicle.Testing.appended_events(client, &1))
             |> Enum.map(& &1.event)
             |> Enum.filter(&match?(%TestingCollectionUniqueValueFollowUp{}, &1))

    assert second_event_source_id
           |> then(&Chronicle.Testing.appended_events(client, &1))
           |> Enum.map(& &1.event)
           |> Enum.filter(&match?(%TestingCollectionUniqueValueFollowUp{}, &1)) == []
  end
end
```
