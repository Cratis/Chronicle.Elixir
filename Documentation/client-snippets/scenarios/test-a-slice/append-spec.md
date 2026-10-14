```elixir
defmodule MyApp.Events.TestSliceAppendBookAdded do
  use Chronicle.Events.EventType, id: "test-slice-append-book-added"

  defstruct [:title, :isbn]
end

defmodule MyApp.TestSliceAppendTest do
  # Runs against an in-memory kernel, so it needs no Chronicle server.
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestSliceAppendBookAdded]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestSliceAppendBookAdded

  test "adding a book appends a BookAdded event", %{chronicle: client} do
    book_id = "book-#{System.unique_integer([:positive])}"

    result =
      EventLog.append(
        book_id,
        %TestSliceAppendBookAdded{title: "The Pragmatic Programmer", isbn: "978-0135957059"},
        client: client
      )

    assert result == :ok

    assert_appended(client, TestSliceAppendBookAdded, event_source_id: book_id)
  end
end
```
