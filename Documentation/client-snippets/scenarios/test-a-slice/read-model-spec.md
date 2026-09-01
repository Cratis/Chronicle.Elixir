```elixir
defmodule MyApp.Events.TestSliceReadModelBookAdded do
  use Chronicle.Events.EventType, id: "test-slice-read-model-book-added"

  defstruct [:title, :isbn]
end

defmodule MyApp.Events.TestSliceReadModelBookBorrowed do
  use Chronicle.Events.EventType, id: "test-slice-read-model-book-borrowed"

  defstruct [:borrowed_by]
end

defmodule MyApp.ReadModels.TestSliceReadModelBook do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{TestSliceReadModelBookAdded, TestSliceReadModelBookBorrowed}

  defstruct id: nil, title: nil, on_loan: false, borrowed_by: nil

  from TestSliceReadModelBookAdded,
    set: [id: :event_source_id, title: :title, on_loan: false]

  from TestSliceReadModelBookBorrowed,
    set: [on_loan: true, borrowed_by: :borrowed_by]
end

defmodule MyApp.TestSliceReadModelTest do
  # Exercises the real client SDK against a running Chronicle event store,
  # so it's skipped here; remove the tag to run it against a live store.
  use ExUnit.Case, async: true
  @moduletag :skip

  alias MyApp.Events.{TestSliceReadModelBookAdded, TestSliceReadModelBookBorrowed}
  alias MyApp.ReadModels.TestSliceReadModelBook

  test "borrowing a book marks it on loan" do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    Chronicle.append(book_id, %TestSliceReadModelBookAdded{
      title: "The Pragmatic Programmer",
      isbn: "978-0135957059"
    })

    Chronicle.append(book_id, %TestSliceReadModelBookBorrowed{borrowed_by: "Ada Lovelace"})

    book = Chronicle.read_model(TestSliceReadModelBook, book_id)

    assert book.on_loan
    assert book.borrowed_by == "Ada Lovelace"
  end
end
```
