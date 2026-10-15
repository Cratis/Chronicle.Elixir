```elixir
defmodule MyApp.Events.TestingScenarioReopeningBooksReopened do
  use Chronicle.Events.EventType, id: "testing-scenario-reopening-books-reopened"

  defstruct [:period]
end

defmodule MyApp.Events.TestingScenarioReopeningBooksClosed do
  use Chronicle.Events.EventType, id: "testing-scenario-reopening-books-closed"

  defstruct [:period]

  closes_stream event_stream_id_from: :period,
                dimensions: [:event_source_id],
                reopened_by: [MyApp.Events.TestingScenarioReopeningBooksReopened]
end

defmodule MyApp.Events.TestingScenarioReopeningEntryPosted do
  use Chronicle.Events.EventType, id: "testing-scenario-reopening-entry-posted"

  defstruct [:description]
end

# The in-memory kernel does not model closing events, so this spec needs a real kernel.
defmodule MyApp.TestingScenarioReopeningEventTest do
  use ExUnit.Case

  @moduletag :integration

  alias Chronicle.EventSequences.EventLog

  alias MyApp.Events.{
    TestingScenarioReopeningBooksClosed,
    TestingScenarioReopeningBooksReopened,
    TestingScenarioReopeningEntryPosted
  }

  setup do
    name = :"reopening_event_#{System.unique_integer([:positive])}"

    {:ok, client} =
      Chronicle.Testing.Integration.setup_isolated_client(
        [
          event_types: [
            MyApp.Events.TestingScenarioReopeningBooksClosed,
            MyApp.Events.TestingScenarioReopeningBooksReopened,
            MyApp.Events.TestingScenarioReopeningEntryPosted
          ]
        ],
        name
      )

    %{chronicle: client}
  end

  test "the reopening event lifts the closure", %{chronicle: client} do
    :ok =
      EventLog.append("ledger-1", %TestingScenarioReopeningBooksClosed{period: "2026-04"}, client: client)

    # The reopening fact is accepted inside the scope it reopens.
    assert :ok =
             EventLog.append(
               "ledger-1",
               %TestingScenarioReopeningBooksReopened{period: "2026-04"},
               client: client
             )

    assert :ok =
             EventLog.append("ledger-1", %TestingScenarioReopeningEntryPosted{description: "Correction"},
               client: client,
               event_stream_type: "ledger",
               event_stream_id: "2026-04"
             )
  end
end
```
