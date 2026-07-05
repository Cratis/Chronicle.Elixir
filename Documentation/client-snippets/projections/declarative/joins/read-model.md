```elixir title="Read model"
defmodule MyApp.ReadModels.DecJoinsUser do
  use Chronicle.ReadModels.ReadModel

  defstruct [:name, :email, :group_id, :group_name, :group_description]
end
```
