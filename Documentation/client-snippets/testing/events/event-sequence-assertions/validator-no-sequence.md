```elixir
defmodule MyApp.Events.TestingSeqAssertValidatorAnyAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-seq-assert-validator-any-author-registered"

  defstruct [:name]
end

defmodule MyApp.Events.TestingSeqAssertValidatorAnyBookAdded do
  use Chronicle.Events.EventType, id: "testing-seq-assert-validator-any-book-added"

  defstruct [:title]
end

defmodule MyApp.TestingSeqAssertValidatorNoSequenceTest do
  use Chronicle.Testing.Case,
    event_types: [MyApp.Events.TestingSeqAssertValidatorAnyAuthorRegistered, MyApp.Events.TestingSeqAssertValidatorAnyBookAdded]

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.{TestingSeqAssertValidatorAnyAuthorRegistered, TestingSeqAssertValidatorAnyBookAdded}

  test "the first event of the matching type carries the expected content", %{chronicle: client} do
    author_id = "author-#{System.unique_integer([:positive])}"

    :ok = EventLog.append(author_id, %TestingSeqAssertValidatorAnyBookAdded{title: "Clean Code"}, client: client)
    :ok = EventLog.append(author_id, %TestingSeqAssertValidatorAnyAuthorRegistered{name: "Jane Smith"}, client: client)

    # No sequence number: take the first event of the matching type.
    first =
      client
      |> Chronicle.Testing.appended_events(author_id)
      |> Enum.find(&match?(%{event: %TestingSeqAssertValidatorAnyAuthorRegistered{}}, &1))

    assert %{event: %TestingSeqAssertValidatorAnyAuthorRegistered{name: "Jane Smith"}} = first
  end
end
```
