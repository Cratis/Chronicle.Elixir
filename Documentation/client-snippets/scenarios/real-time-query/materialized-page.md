```elixir
defmodule MyApp.ReadModels.ScenariosQueryPagedBook do
  defstruct [:title, :on_loan]
end

defmodule MyApp.ScenariosQueryBookPageService do
  alias MyApp.ReadModels.ScenariosQueryPagedBook

  def get_page do
    {:ok, result} = Chronicle.ReadModels.query(ScenariosQueryPagedBook, page: 1, page_size: 20)
    result.instances
  end
end
```
