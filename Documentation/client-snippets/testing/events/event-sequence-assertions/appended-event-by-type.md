```elixir
defmodule MyApp.Events.TestingSeqAssertByTypeAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-by-type-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertByTypeBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-by-type-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertAppendedEventByTypeTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingSeqAssertByTypeAuthorRegistered, MyApp.Events.TestingSeqAssertByTypeBookAdded]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingSeqAssertByTypeAuthorRegistered, TestingSeqAssertByTypeBookAdded}

  test "an event of each type was appended somewhere in the sequence", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertByTypeAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author_id, %TestingSeqAssertByTypeBookAdded{title: "Clean Code"}, client: client)

    assert_appended(client, TestingSeqAssertByTypeAuthorRegistered)
    assert_appended(client, TestingSeqAssertByTypeBookAdded)
  end
end
```
