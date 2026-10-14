```elixir
defmodule MyApp.Events.TestingSeqAssertPositionAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-position-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertPositionBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-position-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertAppendedEventAtPositionTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingSeqAssertPositionAuthorRegistered, MyApp.Events.TestingSeqAssertPositionBookAdded]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingSeqAssertPositionAuthorRegistered, TestingSeqAssertPositionBookAdded}

  test "each event sits at the sequence number it was appended at", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertPositionAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author_id, %TestingSeqAssertPositionBookAdded{title: "Clean Code"}, client: client)

    appended = Chronicle.Testing.appended_events(client, author_id)

    assert [
             %{event: %TestingSeqAssertPositionAuthorRegistered{}, context: %{sequence_number: 0}},
             %{event: %TestingSeqAssertPositionBookAdded{}, context: %{sequence_number: 1}}
           ] = appended
  end
end
```
