```elixir
defmodule MyApp.Events.TestingScenarioFullAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-scenario-full-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingScenarioFullBookAdded do
  use Chronicle.Events.EventType, id: "testing-scenario-full-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingScenarioFullExampleTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingScenarioFullAuthorRegistered, MyApp.Events.TestingScenarioFullBookAdded]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingScenarioFullAuthorRegistered, TestingScenarioFullBookAdded}

  setup %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    # Given: an author who is already registered
    :ok = EventLog.append(author_id, %TestingScenarioFullAuthorRegistered{name: "Jane Smith"}, client: client)

    %{author_id: author_id}
  end

  describe "when adding a book to an author" do
    setup %{chronicle: client, author_id: author_id} do
      {:ok, result} =
        EventLog.append_with_result(author_id, %TestingScenarioFullBookAdded{title: "Clean Code"}, client: client)

      %{result: result}
    end

    test "appends successfully", %{result: result} do
      assert result.success?
    end

    test "appends the book added event after the author", %{chronicle: client, author_id: author_id, result: result} do
      assert result.sequence_number == 1
      assert_appended(client, %TestingScenarioFullBookAdded{title: "Clean Code"}, event_source_id: author_id)
    end
  end
end
```
