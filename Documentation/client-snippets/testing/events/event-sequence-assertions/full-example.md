```elixir
defmodule MyApp.Events.TestingSeqAssertFullAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-full-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertFullBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-full-book-added"

  defstruct [:title]
end

defmodule MyApp.Events.TestingSeqAssertFullLibraryCreated do
  use Chronicle.Events.EventType, id: "testing-seq-assert-full-library-created"

  defstruct [:name]
end

defmodule MyApp.TestingSeqAssertFullExampleTest do
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingSeqAssertFullLibraryCreated,
      MyApp.Events.TestingSeqAssertFullAuthorRegistered,
      MyApp.Events.TestingSeqAssertFullBookAdded
    ]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingSeqAssertFullAuthorRegistered, TestingSeqAssertFullBookAdded, TestingSeqAssertFullLibraryCreated}

  test "registering an author and adding a book appends both events in order", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    # Given an event that is already in the sequence
    :ok = EventLog.append(author_id, %TestingSeqAssertFullLibraryCreated{name: "Main Library"}, client: client)

    :ok = EventLog.append(author_id, %TestingSeqAssertFullAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author_id, %TestingSeqAssertFullBookAdded{title: "Clean Code"}, client: client)

    # The tail includes the seeded event (0) plus the two appended events (1, 2)
    assert {:ok, 2} = EventLog.get_tail_sequence_number(nil, client: client)

    [_seeded, author, book] = Chronicle.Testing.appended_events(client, author_id)

    assert %{event: %TestingSeqAssertFullAuthorRegistered{name: "Jane Smith"}, context: %{sequence_number: 1}} = author
    assert %{event: %TestingSeqAssertFullBookAdded{title: "Clean Code"}, context: %{sequence_number: 2}} = book
  end
end
```
