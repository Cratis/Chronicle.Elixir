```elixir
defmodule MyApp.Events.WebhooksIndexAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "webhooks-index-account-opened"

  defstruct [:owner_name]
end

defmodule MyApp.WebhooksIndexRegister do
  alias MyApp.Events.WebhooksIndexAccountOpened

  def register_webhook do
    Cratis.Chronicle.WebHooks.register(
      "account-events",
      "https://example.com/chronicle/webhooks",
      fn builder ->
        builder
        |> Cratis.Chronicle.WebHooks.DefinitionBuilder.with_event_type(WebhooksIndexAccountOpened)
        |> Cratis.Chronicle.WebHooks.DefinitionBuilder.with_header("x-source", "my-app")
        |> Cratis.Chronicle.WebHooks.DefinitionBuilder.with_bearer_token(System.fetch_env!("WEBHOOK_TOKEN"))
      end
    )
  end
end
```
