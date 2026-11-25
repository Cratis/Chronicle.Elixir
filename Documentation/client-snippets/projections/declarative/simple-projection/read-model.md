```elixir
defmodule MyApp.ReadModels.DecSimpleUser do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :created_at]
end
```
