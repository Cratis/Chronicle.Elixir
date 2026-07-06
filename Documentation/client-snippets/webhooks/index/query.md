```elixir
defmodule MyApp.WebhooksIndexQuery do
  def get_all_webhooks do
    Chronicle.WebHooks.all()
  end
end
```
