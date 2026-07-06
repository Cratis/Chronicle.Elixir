```elixir
defmodule MyApp.ReadModels.DecSimpleUser do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :created_at]
end
```
