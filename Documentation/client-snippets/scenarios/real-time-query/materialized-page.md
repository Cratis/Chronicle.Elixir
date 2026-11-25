```elixir
defmodule MyApp.ReadModels.ScenariosQueryPagedBook do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct title: "", on_loan: false
end

defmodule MyApp.ScenariosQueryBookPageService do
  alias MyApp.ReadModels.ScenariosQueryPagedBook

  def get_page do
    {:ok, result} = Cratis.Chronicle.ReadModels.query(ScenariosQueryPagedBook, page: 0, page_size: 20)
    result.instances
  end
end
```
