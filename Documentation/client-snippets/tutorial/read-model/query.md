```elixir
defmodule MyApp.ReadModels.TutorialQueryBook do
  defstruct [:title, :on_loan]
end

defmodule MyApp.TutorialQueryBooksService do
  alias MyApp.ReadModels.TutorialQueryBook

  def on_loan do
    {:ok, books} = Chronicle.all(TutorialQueryBook)
    Enum.filter(books, & &1.on_loan)
  end
end
```
