```elixir
defmodule MyApp.Events.TestingReadModelScenarioSomeEvent do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-some-event"

  defstruct [:value]
end

defmodule MyApp.Events.TestingReadModelScenarioSomeOtherEvent do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-some-other-event"

  defstruct [:value]
end

defmodule MyApp.ReadModels.TestingReadModelScenarioMyReadModel do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.TestingReadModelScenarioSomeEvent

  defstruct id: nil, value: nil

  from TestingReadModelScenarioSomeEvent, set: [id: :event_source_id, value: :value]
end

defmodule MyApp.TestingReadModelScenarioBasicTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.{
    TestingReadModelScenarioSomeEvent,
    TestingReadModelScenarioSomeOtherEvent
  }

  alias MyApp.ReadModels.TestingReadModelScenarioMyReadModel

  test "only the matching event projects a value" do
    event_source_id = "item-#{System.unique_integer([:positive])}"

    {:ok, instance} =
      Chronicle.Testing.Projections.apply_event(
        TestingReadModelScenarioMyReadModel,
        nil,
        %TestingReadModelScenarioSomeEvent{value: "expected value"},
        event_source_id
      )

    # An event with no matching `from/2` declaration leaves the instance unchanged.
    {:ok, ^instance} =
      Chronicle.Testing.Projections.apply_event(
        TestingReadModelScenarioMyReadModel,
        instance,
        %TestingReadModelScenarioSomeOtherEvent{value: 42},
        event_source_id
      )

    assert instance.value == "expected value"
  end
end
```
