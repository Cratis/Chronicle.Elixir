```elixir
defmodule MyApp.ReadModels.PdlExpressionsUserReadModel do
  # name: requires string, login_count: requires number,
  # is_active: requires boolean, created_at: requires timestamp
  defstruct name: "", login_count: 0, is_active: false, created_at: nil
end
```
