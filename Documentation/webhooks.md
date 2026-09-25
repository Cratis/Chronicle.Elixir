---
title: Webhooks
description: Register Chronicle webhooks from Elixir, as discoverable modules or at runtime, and inspect the registered webhooks.
---

`Chronicle.WebHooks` provides an idiomatic Elixir API for registering and inspecting Chronicle webhooks.

Webhooks let Chronicle push observed events to external HTTP endpoints.

## Discoverable webhooks

Discoverable webhooks follow the same pattern as projections and constraints: define them as modules and Chronicle exposes metadata through `__chronicle_webhook__/1`.

```elixir
defmodule MyApp.WebHooks.AccountEvents do
  use Chronicle.WebHooks.Webhook,
    id: "account-events",
    target_url: "https://example.com/chronicle/webhooks",
    event_sequence_id: "event-log"

  alias Chronicle.WebHooks.DefinitionBuilder

  @impl true
  def define(builder) do
    builder
    |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
    |> DefinitionBuilder.with_event_type(MyApp.Events.FundsDeposited)
    |> DefinitionBuilder.with_header("x-source", "my-app")
    |> DefinitionBuilder.with_bearer_token(System.fetch_env!("WEBHOOK_TOKEN"))
  end
end
```

When `Chronicle.Client` starts with `otp_app: :my_app`, discoverable webhooks are found automatically and registered on startup.

```elixir
{Chronicle.Client,
  connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
  event_store: "banking",
  otp_app: :my_app}
```

You can also register explicit modules:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
  event_store: "banking",
  webhooks: [MyApp.WebHooks.AccountEvents]}
```

## Imperative registration

Register a webhook without defining a module:

```elixir
:ok =
  Chronicle.WebHooks.register(
    "account-events",
    "https://example.com/chronicle/webhooks",
    fn builder ->
      builder
      |> Chronicle.WebHooks.DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
      |> Chronicle.WebHooks.DefinitionBuilder.with_basic_auth("chronicle", System.fetch_env!("WEBHOOK_PASSWORD"))
      |> Chronicle.WebHooks.DefinitionBuilder.with_header("x-source", "my-app")
    end
  )
```

## Builder API

`Chronicle.WebHooks.DefinitionBuilder` is immutable and pipeline-friendly.

```elixir
builder
|> DefinitionBuilder.on_event_sequence("audit-sequence")
|> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
|> DefinitionBuilder.with_basic_auth("user", "password")
|> DefinitionBuilder.with_bearer_token("token")
|> DefinitionBuilder.with_oauth("https://login.example.com", "client-id", "client-secret")
|> DefinitionBuilder.with_header("x-source", "my-app")
|> DefinitionBuilder.not_replayable()
|> DefinitionBuilder.not_active()
```

If you don't select any event types, the webhook uses the event types the client was given in `:event_types` or discovered in your application. When that list is empty, for example with `discover: false` and no `:event_types`, it falls back to every event type module loaded in the VM. Select event types explicitly to control exactly what the webhook receives.

## Query and remove webhooks

```elixir
{:ok, webhooks} = Chronicle.WebHooks.all()
:ok = Chronicle.WebHooks.remove("account-events")
```

Registered webhooks are returned as `%Chronicle.WebHooks.Definition{}` with:

- `:id`
- `:event_sequence_id`
- `:event_types`
- `:target`
- `:replayable?`
- `:active?`

The nested `%Chronicle.WebHooks.Target{}` contains:

- `:url`
- `:headers`
- `:authorization`

When you build a definition locally, authorization is one of:

- `{:basic, %{username: ..., password: ...}}`
- `{:bearer, %{token: ...}}`
- `{:oauth, %{authority: ..., client_id: ..., client_secret: ...}}`
- `nil`

Chronicle doesn't return credentials when you read webhooks back, so `:authorization` is always `nil` on definitions from `Chronicle.WebHooks.all/1`.

## Manual discovery

```elixir
webhooks = Chronicle.WebHooks.discover()
:ok = Chronicle.WebHooks.register_discovered()
```

## Top-level convenience helpers

`Chronicle` also delegates to the webhook API:

```elixir
{:ok, webhooks} = Chronicle.get_webhooks()
:ok = Chronicle.register_discovered_webhooks()
:ok = Chronicle.remove_webhook("account-events")
```
