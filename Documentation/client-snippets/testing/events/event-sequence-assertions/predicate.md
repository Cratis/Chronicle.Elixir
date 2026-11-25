```elixir
defmodule MyApp.Events.TestingSeqAssertPredicateAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "testing-seq-assert-predicate-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertPredicateBookAdded do
  use Cratis.Chronicle.Events.EventType, id: "testing-seq-assert-predicate-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertPredicateTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingSeqAssertPredicateAuthorRegistered, MyApp.Events.TestingSeqAssertPredicateBookAdded]

  import Cratis.Chronicle.Testing.Assertions

  alias Cratis.Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingSeqAssertPredicateAuthorRegistered

  test "an event satisfies a predicate", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertPredicateAuthorRegistered{name: "Jane Smith"}, client: client)

    # The predicate is called with every appended event, so it answers false for other types.
    jane? = fn
      %TestingSeqAssertPredicateAuthorRegistered{name: name} -> name == "Jane Smith"
      _other -> false
    end

    # Without a sequence number — any matching event
    assert_appended(client, jane?)

    # At a specific sequence number
    [first | _] = Cratis.Chronicle.Testing.appended_events(client, author_id)
    assert first.context.sequence_number == 0
    assert jane?.(first.event)
  end
end
```
