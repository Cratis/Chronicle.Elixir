```elixir
defmodule MyApp.Events.TestingScenarioSourcesAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-scenario-sources-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingScenarioSourcesBookAdded do
  use Chronicle.Events.EventType, id: "testing-scenario-sources-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingScenarioGivenMultipleSourcesTest do
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingScenarioSourcesAuthorRegistered]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingScenarioSourcesAuthorRegistered

  test "events can be given for several event sources", %{chronicle: client} do
    author1_id = "author-#{System.unique_integer([:positive])}"
    author2_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author1_id, %TestingScenarioSourcesAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author2_id, %TestingScenarioSourcesAuthorRegistered{name: "John Doe"}, client: client)

    assert_appended(client, %TestingScenarioSourcesAuthorRegistered{name: "Jane Smith"}, event_source_id: author1_id)
    assert_appended(client, %TestingScenarioSourcesAuthorRegistered{name: "John Doe"}, event_source_id: author2_id)
  end
end
```
