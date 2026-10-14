```elixir
defmodule MyApp.Events.TestingScenarioGivenAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-scenario-given-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingScenarioGivenBookAdded do
  use Chronicle.Events.EventType, id: "testing-scenario-given-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingScenarioGivenTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingScenarioGivenAuthorRegistered, MyApp.Events.TestingScenarioGivenBookAdded]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingScenarioGivenAuthorRegistered, TestingScenarioGivenBookAdded}

  test "appending after the given events succeeds", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    # Given: events already in the sequence for the event source
    :ok =
      EventLog.append_many(
        author_id,
        [%TestingScenarioGivenAuthorRegistered{name: "John Doe"}, %TestingScenarioGivenBookAdded{title: "Clean Code"}],
        client: client
      )

    {:ok, result} =
      EventLog.append_with_result(
        author_id,
        %TestingScenarioGivenBookAdded{title: "The Pragmatic Programmer"},
        client: client
      )

    assert result.success?
  end
end
```
