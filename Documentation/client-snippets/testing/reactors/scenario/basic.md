```elixir
defmodule MyApp.Events.TestingReactorScenarioSomeEvent do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-some-event"

  defstruct [:value]
end

defmodule MyApp.Events.TestingReactorScenarioSomeOtherEvent do
  use Chronicle.Events.EventType, id: "testing-reactor-scenario-some-other-event"

  defstruct [:value]
end

defmodule MyApp.TestingReactorScenarioService do
  @callback do_something(String.t()) :: :ok
end

# The reactor resolves its collaborator from the application environment, so a spec
# can swap in a recording stand-in.
defmodule MyApp.Reactors.TestingReactorScenarioMyReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.TestingReactorScenarioSomeEvent

  @handles TestingReactorScenarioSomeEvent

  @impl true
  def handle(%TestingReactorScenarioSomeEvent{value: value}, _context) do
    service = Application.fetch_env!(:my_app, :testing_reactor_scenario_service)
    service.do_something(value)
  end
end

defmodule MyApp.TestingReactorScenarioRecordingService do
  @behaviour MyApp.TestingReactorScenarioService

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def do_something(value), do: Agent.update(__MODULE__, &[value | &1])
end

defmodule MyApp.TestingReactorScenarioBasicTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingReactorScenarioSomeEvent,
      MyApp.Events.TestingReactorScenarioSomeOtherEvent
    ],
    reactors: [MyApp.Reactors.TestingReactorScenarioMyReactor]

  alias MyApp.Events.{TestingReactorScenarioSomeEvent, TestingReactorScenarioSomeOtherEvent}
  alias MyApp.TestingReactorScenarioRecordingService, as: Service

  setup do
    {:ok, _service} = Service.start_link()
    Application.put_env(:my_app, :testing_reactor_scenario_service, Service)
    on_exit(fn -> Application.delete_env(:my_app, :testing_reactor_scenario_service) end)
  end

  test "the reactor calls the service for the event it handles", %{chronicle: client} do
    some_id = "some-#{System.unique_integer([:positive])}"

    :ok =
      Chronicle.EventSequences.EventLog.append_many(
        some_id,
        [
          %TestingReactorScenarioSomeEvent{value: "value"},
          %TestingReactorScenarioSomeOtherEvent{value: 42}
        ],
        client: client
      )

    :ok = Chronicle.Testing.wait_for_observers(client)

    # Assert on the side effects the stand-in recorded
    assert Service.calls() == ["value"]
  end
end
```
