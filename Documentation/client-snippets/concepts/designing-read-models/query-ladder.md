```elixir
defmodule MyApp.ReadModels.DesigningReadModelsCustomerListItem do
  defstruct [:id, :name]
end

defmodule MyApp.DesigningReadModelsCustomerListService do
  alias MyApp.ReadModels.DesigningReadModelsCustomerListItem

  def get_all_strongly_consistent do
    # Strongly consistent — Chronicle replays the read model's events on demand
    Chronicle.all(DesigningReadModelsCustomerListItem)
  end

  def get_page_eventually_consistent do
    # Eventually consistent — a page of materialized instances straight from storage
    Chronicle.ReadModels.query(DesigningReadModelsCustomerListItem, page: 1, page_size: 20)
  end
end
```
