```elixir
defmodule MyApp.Events.TestSliceConstraintBookAdded do
  use Chronicle.Events.EventType, id: "test-slice-constraint-book-added"

  defstruct [:title, :isbn]

  unique(:isbn, name: "TestSliceConstraintUniqueIsbn")
end

defmodule MyApp.TestSliceConstraintTest do
  # Runs against an in-memory kernel, which enforces unique constraints on append.
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestSliceConstraintBookAdded]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestSliceConstraintBookAdded

  test "adding a second book with an isbn already in use is rejected", %{chronicle: client} do
    first = "book-#{System.unique_integer([:positive])}"
    second = "book-#{System.unique_integer([:positive])}"

    :ok =
      EventLog.append(
        first,
        %TestSliceConstraintBookAdded{title: "The Pragmatic Programmer", isbn: "978-0135957059"},
        client: client
      )

    result =
      EventLog.append(
        second,
        %TestSliceConstraintBookAdded{
          title: "The Pragmatic Programmer, 2nd ed.",
          isbn: "978-0135957059"
        },
        client: client
      )

    assert_constraint_violation(result, "TestSliceConstraintUniqueIsbn")
    refute_appended(client, TestSliceConstraintBookAdded, event_source_id: second)
  end
end
```
