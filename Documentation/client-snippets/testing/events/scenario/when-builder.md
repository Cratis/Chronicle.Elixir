```elixir
defmodule MyApp.Events.TestingScenarioWhenAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-scenario-when-author-registered"

  unique(:name, name: "TestingScenarioUniqueAuthorName")

  defstruct [:name]
end

defmodule MyApp.TestingScenarioWhenTest do
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingScenarioWhenAuthorRegistered]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingScenarioWhenAuthorRegistered

  test "registering an existing name under a new event source is rejected", %{chronicle: client} do
    existing_author_id = "author-#{System.unique_integer([:positive])}"
    new_author_id = "author-#{System.unique_integer([:positive])}"

    # Given: an author with this name is already registered
    :ok = EventLog.append(existing_author_id, %TestingScenarioWhenAuthorRegistered{name: "John Doe"}, client: client)

    # When: attempt to register the same name under a new event source
    result = EventLog.append(new_author_id, %TestingScenarioWhenAuthorRegistered{name: "John Doe"}, client: client)

    # Then: assert on the returned result
    assert_constraint_violation(result, "TestingScenarioUniqueAuthorName")
  end
end
```
