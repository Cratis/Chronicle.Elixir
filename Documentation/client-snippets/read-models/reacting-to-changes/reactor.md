```elixir
defmodule MyApp.Reactors.AccountNotifier do
  use Chronicle.ReadModels.Reactor, model: MyApp.ReadModels.Account

  @impl true
  def on_added(account, _changeset), do: send_welcome(account)

  @impl true
  def on_modified(account, _changeset), do: send_updated(account)

  @impl true
  def on_removed(key, _changeset), do: send_closed(key)

  defp send_welcome(_account), do: :ok
  defp send_updated(_account), do: :ok
  defp send_closed(_key), do: :ok
end
```
