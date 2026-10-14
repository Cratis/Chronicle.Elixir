```elixir
defmodule MyApp.Events.TestingReadModelScenarioItemAdded do
  use Chronicle.Events.EventType, id: "testing-read-model-scenario-item-added"

  defstruct []
end

defmodule MyApp.ReadModels.TestingReadModelScenarioCountingReadModel do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.TestingReadModelScenarioItemAdded

  defstruct count: 0

  from TestingReadModelScenarioItemAdded, count: :count
end

defmodule MyApp.TestingReadModelScenarioInitialStateTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.TestingReadModelScenarioItemAdded
  alias MyApp.ReadModels.TestingReadModelScenarioCountingReadModel

  test "events are applied on top of an initial state" do
    initial = %TestingReadModelScenarioCountingReadModel{count: 10}

    {:ok, counting} =
      Chronicle.Testing.Projections.apply_event(
        TestingReadModelScenarioCountingReadModel,
        initial,
        %TestingReadModelScenarioItemAdded{},
        "counter-#{System.unique_integer([:positive])}"
      )

    assert counting.count == 11
  end
end
```
