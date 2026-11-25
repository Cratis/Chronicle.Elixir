```elixir
defmodule MyApp.TutorialQueryBooksService do
  alias MyApp.ReadModels.Book

  def on_loan do
    with {:ok, books} <- Cratis.Chronicle.all(Book) do
      {:ok, Enum.filter(books, & &1.on_loan)}
    end
  end
end
```
