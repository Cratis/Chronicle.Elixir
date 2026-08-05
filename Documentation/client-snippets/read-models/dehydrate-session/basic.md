```elixir
defmodule MyApp.ReadModelsDehydrateSession do
  alias MyApp.ReadModels.AccountInfo

  def dehydrate(account_id, session_id) do
    Chronicle.ReadModels.dehydrate_session(AccountInfo, account_id, session_id)
  end
end
```
