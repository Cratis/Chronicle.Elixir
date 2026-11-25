```elixir
defmodule MyApp.TutorialBorrowedBooksService do
  alias MyApp.ReadModels.BorrowedBook

  def all do
    Cratis.Chronicle.all(BorrowedBook)
  end
end
```
