```elixir title="Resolving a passive read model on demand"
defmodule MyApp.UserService do
  def get_user_summary(user_id) do
    Chronicle.ReadModels.get_instance_by_id(MyApp.ReadModels.DecPassiveUserSummary, user_id)
  end
end
```
