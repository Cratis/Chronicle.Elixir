```elixir
defmodule MyApp.Events.TestingSeqAssertTailAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "testing-seq-assert-tail-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertTailBookAdded do
  use Cratis.Chronicle.Events.EventType, id: "testing-seq-assert-tail-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertTailSequenceNumberTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingSeqAssertTailAuthorRegistered, MyApp.Events.TestingSeqAssertTailBookAdded]

  alias Cratis.Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingSeqAssertTailAuthorRegistered, TestingSeqAssertTailBookAdded}

  test "the tail is the sequence number of the last appended event", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertTailAuthorRegistered{name: "Jane Smith"}, client: client)
    :ok = EventLog.append(author_id, %TestingSeqAssertTailBookAdded{title: "Clean Code"}, client: client)

    # Sequence numbers are zero-based: two events put the tail at 1.
    assert {:ok, 1} = EventLog.get_tail_sequence_number(nil, client: client)
  end
end
```
