```elixir
defmodule MyApp.Events.TestingSeqAssertValidatorAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-validator-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertValidatorBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-validator-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertValidatorTest do
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingSeqAssertValidatorAuthorRegistered]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingSeqAssertValidatorAuthorRegistered

  test "the event at sequence number 0 carries the expected content", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertValidatorAuthorRegistered{name: "Jane Smith"}, client: client)

    [first | _] = Chronicle.Testing.appended_events(client, author_id)

    # Matching on the decoded event is the validator: it fails unless the type and content match.
    assert %{event: %TestingSeqAssertValidatorAuthorRegistered{name: "Jane Smith"}, context: %{sequence_number: 0}} =
             first
  end
end
```
