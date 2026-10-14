```elixir
defmodule MyApp.Events.TestingAssertionsHappyPathAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-assertions-happy-path-author-registered"

  defstruct [:name]
end

defmodule MyApp.TestingAssertionsHappyPathTest do
  use ExUnit.Case, async: true

  import Chronicle.Testing.Assertions

  alias MyApp.Events.TestingAssertionsHappyPathAuthorRegistered

  test "appending a new author succeeds" do
    {:ok, client} =
      Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsHappyPathAuthorRegistered]
      )

    on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)

    author_id = "author-#{System.unique_integer([:positive])}"

    result =
      Chronicle.EventSequences.EventLog.append(
        author_id,
        %TestingAssertionsHappyPathAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    assert result == :ok
    assert_appended(client, TestingAssertionsHappyPathAuthorRegistered, event_source_id: author_id)
  end
end
```
