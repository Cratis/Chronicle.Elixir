```elixir
defmodule MyApp.BookQueryService do
  alias MyApp.ReadModels.GetStartedBook
  alias MyApp.ReadModels.GetStartedBorrowedBook

  def query_books do
    {:ok, books} = Cratis.Chronicle.all(GetStartedBook)
    {:ok, borrowed_books} = Cratis.Chronicle.all(GetStartedBorrowedBook)

    {books, borrowed_books}
  end
end
```
