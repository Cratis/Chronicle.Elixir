```elixir
defmodule MyApp.Events.TestingReactorScenarioReminderVibeStarted do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-reminder-vibe-started"

  defstruct [:host]
end

defmodule MyApp.Events.TestingReactorScenarioSendReminder do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-send-reminder"

  defstruct [:host]
end

defmodule MyApp.Reactors.TestingReactorScenarioReminderReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{TestingReactorScenarioReminderVibeStarted, TestingReactorScenarioSendReminder}

  @handles TestingReactorScenarioReminderVibeStarted

  @impl true
  def handle(%TestingReactorScenarioReminderVibeStarted{host: host}, _context),
    do: {:ok, %TestingReactorScenarioSendReminder{host: host}}
end

defmodule MyApp.TestingReactorScenarioProducedSideEffectsTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingReactorScenarioReminderVibeStarted,
      MyApp.Events.TestingReactorScenarioSendReminder
    ],
    reactors: [MyApp.Reactors.TestingReactorScenarioReminderReactor]

  import Chronicle.Testing.Assertions

  alias MyApp.Events.{TestingReactorScenarioReminderVibeStarted, TestingReactorScenarioSendReminder}

  test "a started vibe produces a reminder for the host", %{chronicle: client} do
    vibe_id = "vibe-#{System.unique_integer([:positive])}"

    :ok =
      Chronicle.EventSequences.EventLog.append(
        vibe_id,
        %TestingReactorScenarioReminderVibeStarted{host: "Ada"},
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    assert_appended(client, %TestingReactorScenarioSendReminder{host: "Ada"}, event_source_id: vibe_id)
  end
end
```
