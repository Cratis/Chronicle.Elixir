```elixir
defmodule MyApp.Events.TestingPerRunReactorEvent do
  use Chronicle.Events.EventType, id: "testing-per-run-reactor-event"

  defstruct [:value]
end

defmodule MyApp.Reactors.TestingPerRunReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingPerRunReactorEvent

  @handles TestingPerRunReactorEvent

  @impl true
  def handle(%TestingPerRunReactorEvent{}, _context), do: :ok
end

defmodule MyApp.TestingPerRunReactorExampleTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingPerRunReactorEvent

  test "a run registers only the artifacts it names" do
    # The artifacts belong to this run's client, not to the whole application.
    {:ok, client} =
      Chronicle.Testing.start_supervised_client(
        event_types: [TestingPerRunReactorEvent],
        reactors: [MyApp.Reactors.TestingPerRunReactor]
      )

    on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)

    :ok = EventLog.append("event-source-1", %TestingPerRunReactorEvent{value: "example"}, client: client)
    :ok = Chronicle.Testing.wait_for_observers(client)
  end
end
```
