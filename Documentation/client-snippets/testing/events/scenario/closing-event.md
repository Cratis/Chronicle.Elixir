```elixir
defmodule MyApp.Events.TestingScenarioBooksReopened do
  use Chronicle.Events.EventType, id: "testing-scenario-books-reopened"

  defstruct [:period]
end

defmodule MyApp.Events.TestingScenarioBooksClosed do
  use Chronicle.Events.EventType, id: "testing-scenario-books-closed"

  defstruct [:period]

  # The stream id comes from the period. The scope is the event source and that stream id.
  closes_stream event_stream_id_from: :period,
                dimensions: [:event_source_id],
                reopened_by: [MyApp.Events.TestingScenarioBooksReopened]
end

defmodule MyApp.Events.TestingScenarioEntryPosted do
  use Chronicle.Events.EventType, id: "testing-scenario-entry-posted"

  defstruct [:description]
end

# The in-memory kernel does not model closing events, so this spec needs a real kernel.
defmodule MyApp.TestingScenarioClosingEventTest do
  use ExUnit.Case

  @moduletag :integration

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingScenarioBooksClosed, TestingScenarioEntryPosted}

  setup do
    name = :"closing_event_#{System.unique_integer([:positive])}"

    {:ok, client} =
      Chronicle.Testing.Integration.setup_isolated_client(
        [
          event_types: [
            MyApp.Events.TestingScenarioBooksClosed,
            MyApp.Events.TestingScenarioBooksReopened,
            MyApp.Events.TestingScenarioEntryPosted
          ]
        ],
        name
      )

    %{chronicle: client}
  end

  test "a closing event closes the stream it names", %{chronicle: client} do
    :ok = EventLog.append("ledger-1", %TestingScenarioBooksClosed{period: "2026-04"}, client: client)

    # Covered: same event source, stream id taken from the closing event's period.
    late =
      EventLog.append("ledger-1", %TestingScenarioEntryPosted{description: "Late invoice"},
        client: client,
        event_stream_type: "ledger",
        event_stream_id: "2026-04"
      )

    assert_constraint_violation(late)

    # Not covered: another event source, and the next period.
    assert :ok =
             EventLog.append("ledger-2", %TestingScenarioEntryPosted{description: "Open"},
               client: client,
               event_stream_type: "ledger",
               event_stream_id: "2026-04"
             )

    assert :ok =
             EventLog.append("ledger-1", %TestingScenarioEntryPosted{description: "Next"},
               client: client,
               event_stream_type: "ledger",
               event_stream_id: "2026-05"
             )
  end
end
```
