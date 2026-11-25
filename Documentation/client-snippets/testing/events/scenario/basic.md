```elixir
defmodule MyApp.Events.TestingScenarioBasicAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "testing-scenario-basic-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingScenarioBasicBookAdded do
  use Cratis.Chronicle.Events.EventType, id: "testing-scenario-basic-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingScenarioBasicTest do
  use Cratis.Chronicle.Testing.Case, event_types: [MyApp.Events.TestingScenarioBasicAuthorRegistered]

  alias Cratis.Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingScenarioBasicAuthorRegistered

  test "appending an event succeeds", %{chronicle: client} do
    {:ok, result} =
      EventLog.append_with_result(
        "author-#{System.unique_integer([:positive])}",
        %TestingScenarioBasicAuthorRegistered{name: "John Doe"},
        client: client
      )

    assert result.success?
  end
end
```
