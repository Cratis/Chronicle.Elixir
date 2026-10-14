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

  defstruct id: nil, title: nil, borrowed_by: nil

  from TestSliceReadModelBookAdded,
    set: [id: :event_source_id, title: :title]

  from TestSliceReadModelBookBorrowed,
    set: [borrowed_by: :borrowed_by]
end

defmodule MyApp.TestSliceReadModelTest do
  # Evaluates the read model's `from/2` declarations in memory, so it needs no Chronicle server.
  use ExUnit.Case, async: true

  alias Chronicle.Testing.Projections
  alias MyApp.Events.{TestSliceReadModelBookAdded, TestSliceReadModelBookBorrowed}
  alias MyApp.ReadModels.TestSliceReadModelBook

  test "borrowing a book records who has it" do
    book_id = "book-#{System.unique_integer([:positive])}"

    {:ok, book} =
      Projections.apply_event(
        TestSliceReadModelBook,
        nil,
        %TestSliceReadModelBookAdded{title: "The Pragmatic Programmer", isbn: "978-0135957059"},
        book_id
      )

    assert book.borrowed_by == nil

    {:ok, book} =
      Projections.apply_event(
        TestSliceReadModelBook,
        book,
        %TestSliceReadModelBookBorrowed{borrowed_by: "Ada Lovelace"},
        book_id
      )

    assert book.borrowed_by == "Ada Lovelace"
  end
end
```
