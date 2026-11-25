```elixir
defmodule MyApp.WebhooksIndexQuery do
  def get_all_webhooks do
    Cratis.Chronicle.WebHooks.all()
  end
end
```
