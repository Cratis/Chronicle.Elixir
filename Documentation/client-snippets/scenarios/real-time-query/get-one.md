```elixir
defmodule MyApp.ReadModels.ScenariosQueryBook do
  use Chronicle.ReadModels.ReadModel

  defstruct title: "", on_loan: false
end

defmodule MyApp.ScenariosQueryBookService do
  alias MyApp.ReadModels.ScenariosQueryBook

  def get_book(book_id) do
    Chronicle.read_model(ScenariosQueryBook, book_id)
  end
end
```
