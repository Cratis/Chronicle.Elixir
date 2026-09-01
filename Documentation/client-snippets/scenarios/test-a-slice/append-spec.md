```elixir
defmodule MyApp.Events.TestSliceAppendBookAdded do
  use Chronicle.Events.EventType, id: "test-slice-append-book-added"

  defstruct [:title, :isbn]

  unique(:isbn, name: "TestSliceAppendUniqueIsbn")
end

defmodule MyApp.TestSliceAppendTest do
  # Exercises the real client SDK against a running Chronicle event store,
  # so it's skipped here; remove the tag to run it against a live store.
  use ExUnit.Case, async: true
  @moduletag :skip

  alias MyApp.Events.TestSliceAppendBookAdded

  test "adding a book succeeds" do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    result =
      Chronicle.append(book_id, %TestSliceAppendBookAdded{
        title: "The Pragmatic Programmer",
        isbn: "978-0135957059"
      })

    assert result == :ok
  end
end
```
