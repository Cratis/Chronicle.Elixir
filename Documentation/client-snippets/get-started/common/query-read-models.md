```elixir
defmodule MyApp.BookQueryService do
  alias MyApp.ReadModels.GetStartedBook
  alias MyApp.ReadModels.GetStartedBorrowedBook

  def query_books do
    {:ok, books} = Chronicle.all(GetStartedBook)
    {:ok, borrowed_books} = Chronicle.all(GetStartedBorrowedBook)

    {books, borrowed_books}
  end
end
```
