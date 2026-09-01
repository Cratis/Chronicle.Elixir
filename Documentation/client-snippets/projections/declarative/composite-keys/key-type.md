```elixir title="Composite key type"
defmodule MyApp.ReadModels.CompositeOrderKey do
  defstruct [:customer_id, :order_number]
end
```
