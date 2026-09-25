```elixir
defmodule MyApp.ReadModels.ScenariosQueryGetAllBook do
  use Chronicle.ReadModels.ReadModel

  defstruct title: "", on_loan: false
end

defmodule MyApp.ScenariosQueryOnLoanBooksService do
  alias MyApp.ReadModels.ScenariosQueryGetAllBook

  def get_on_loan do
    {:ok, books} = Chronicle.all(ScenariosQueryGetAllBook)
    Enum.filter(books, & &1.on_loan)
  end
end
```
