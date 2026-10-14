```elixir
defmodule MyApp.Events.TestingSeqAssertSourceAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-source-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertSourceBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-source-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertByEventSourceTest do
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingSeqAssertSourceAuthorRegistered]

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingSeqAssertSourceAuthorRegistered

  test "assertions can be narrowed to one event source", %{chronicle: client} do
    author1 = "author-#{System.unique_integer([:positive])}"
    author2 = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author1, %TestingSeqAssertSourceAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author2, %TestingSeqAssertSourceAuthorRegistered{name: "John Doe"}, client: client)

    # With a sequence number and the exact content
    [first] = Chronicle.Testing.appended_events(client, author1)

    assert %{
             event: %TestingSeqAssertSourceAuthorRegistered{name: "Jane Smith"},
             context: %{sequence_number: 0, event_source_id: ^author1}
           } = first

    # Without a sequence number — any matching event for the event source
    assert_appended(client, %TestingSeqAssertSourceAuthorRegistered{name: "John Doe"}, event_source_id: author2)

    # With a predicate instead of the exact content
    assert_appended(client, &match?(%TestingSeqAssertSourceAuthorRegistered{name: "Jane Smith"}, &1),
      event_source_id: author1
    )
  end
end
```
