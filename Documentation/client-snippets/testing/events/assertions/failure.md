```elixir
defmodule MyApp.Events.TestingAssertionsFailureAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-assertions-failure-author-registered"

  defstruct [:name]

  unique(:name, name: "TestingAssertionsFailureUniqueAuthorName")
end

defmodule MyApp.TestingAssertionsFailureTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.TestingAssertionsFailureAuthorRegistered

  test "appending a duplicate unique name fails" do
    {:ok, client} =
      Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsFailureAuthorRegistered]
      )

    on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)

    :ok =
      Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsFailureAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    result =
      Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsFailureAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    assert {:error, {:constraint_violations, _violations}} = result
  end
end
```
