```elixir
defmodule MyApp.Events.TestingScenarioManualCloseReportEdited do
  use Chronicle.Events.EventType, id: "testing-scenario-manual-close-report-edited"

  defstruct [:text]
end

# The in-memory kernel does not model closed streams, so this spec needs a real kernel.
defmodule MyApp.TestingScenarioManualCloseTest do
  use ExUnit.Case

  @moduletag :integration

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.{EventLog, Streams}
  alias MyApp.Events.TestingScenarioManualCloseReportEdited

  setup do
    name = :"manual_close_#{System.unique_integer([:positive])}"

    {:ok, client} =
      Chronicle.Testing.Integration.setup_isolated_client(
        [event_types: [MyApp.Events.TestingScenarioManualCloseReportEdited]],
        name
      )

    %{chronicle: client}
  end

  test "a closed stream refuses later events", %{chronicle: client} do
    {:ok, _sequence_number} =
      Streams.complete_scope(client: client, event_source_id: "report-1", event_stream_id: "2026-04")

    edit =
      EventLog.append("report-1", %TestingScenarioManualCloseReportEdited{text: "Late edit"},
        client: client,
        event_stream_type: "monthly-report",
        event_stream_id: "2026-04"
      )

    assert_constraint_violation(edit)

    {:ok, closed_streams} = Streams.closed(client: client)
    assert length(closed_streams) == 1
  end
end
```
