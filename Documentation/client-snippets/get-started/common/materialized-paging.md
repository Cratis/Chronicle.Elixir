```elixir
defmodule MyApp.BookPagingService do
  alias MyApp.ReadModels.GetStartedBook

  def get_page do
    {:ok, result} = Cratis.Chronicle.ReadModels.query(GetStartedBook, page: 0, page_size: 20)
    result.instances
  end
end
```
