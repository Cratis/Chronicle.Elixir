```elixir
defmodule MyApp.ReadModelsWatch do
  alias MyApp.ReadModels.AccountInfo

  def watch_account_info do
    {:ok, watcher} = Cratis.Chronicle.ReadModels.watch(AccountInfo)
    watcher
  end

  def stop_watching(watcher) do
    Cratis.Chronicle.ReadModels.unwatch(watcher)
  end
end
```
