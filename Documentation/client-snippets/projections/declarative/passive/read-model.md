```elixir title="Read model"
defmodule MyApp.ReadModels.DecPassiveUserSummary do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, login_count: 0, last_login_at: nil]
end
```
