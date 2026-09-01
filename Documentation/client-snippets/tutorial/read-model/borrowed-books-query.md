```elixir
defmodule MyApp.ReadModels.TutorialBorrowedBook do
  defstruct [:member_name]
end

defmodule MyApp.TutorialBorrowedBooksService do
  alias MyApp.ReadModels.TutorialBorrowedBook

  def all do
    {:ok, borrowed_books} = Chronicle.all(TutorialBorrowedBook)
    borrowed_books
  end
end
```
