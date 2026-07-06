```elixir
defmodule MyApp.BookPagingService do
  alias MyApp.ReadModels.GetStartedBook

  def get_page do
    {:ok, result} = Chronicle.ReadModels.query(GetStartedBook, page: 1, page_size: 20)
    result.instances
  end
end
```
