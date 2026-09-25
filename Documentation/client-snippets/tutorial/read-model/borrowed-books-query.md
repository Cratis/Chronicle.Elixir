```elixir
defmodule MyApp.TutorialBorrowedBooksService do
  alias MyApp.ReadModels.BorrowedBook

  def all do
    Chronicle.all(BorrowedBook)
  end
end
```
