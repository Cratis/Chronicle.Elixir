```elixir
defmodule MyApp.Events.TestingAssertionsConstraintViolationAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-assertions-constraint-violation-author-registered"

  defstruct [:name]

  unique(:name, name: "TestingAssertionsConstraintViolationUniqueAuthorName")
end

defmodule MyApp.TestingAssertionsConstraintViolationTest do
  use ExUnit.Case, async: true

  import Chronicle.Testing.Assertions

  alias MyApp.Events.TestingAssertionsConstraintViolationAuthorRegistered

  test "a duplicate unique name reports the named constraint" do
    {:ok, client} =
      Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsConstraintViolationAuthorRegistered]
      )

    on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)

    :ok =
      Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsConstraintViolationAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    result =
      Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsConstraintViolationAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    assert_constraint_violation(result, "TestingAssertionsConstraintViolationUniqueAuthorName")
  end
end
```
