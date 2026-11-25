```elixir
defmodule MyApp.ReadModels.DesigningReadModelsCustomerDetail do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct id: "", name: ""
end

defmodule MyApp.DesigningReadModelsCustomerDetailService do
  alias MyApp.ReadModels.DesigningReadModelsCustomerDetail

  def get_detail(customer_id) do
    Cratis.Chronicle.read_model(DesigningReadModelsCustomerDetail, customer_id)
  end
end
```
