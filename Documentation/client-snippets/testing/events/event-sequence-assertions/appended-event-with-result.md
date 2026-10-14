```elixir
defmodule MyApp.Events.TestingSeqAssertResultAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-result-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertResultBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-result-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertAppendedEventWithResultTest do
  use Chronicle.Testing.Case, event_types: [MyApp.Events.TestingSeqAssertResultAuthorRegistered]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.TestingSeqAssertResultAuthorRegistered

  test "the append result and the stored event can be checked together", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    {:ok, result} =
      EventLog.append_with_result(author_id, %TestingSeqAssertResultAuthorRegistered{name: "Jane Smith"}, client: client)

    [appended] = Chronicle.Testing.appended_events(client, author_id)

    assert result.success?
    assert %TestingSeqAssertResultAuthorRegistered{name: "Jane Smith"} = appended.event
    assert appended.context.event_source_id == author_id
    assert appended.context.sequence_number == result.sequence_number
  end
end
```
