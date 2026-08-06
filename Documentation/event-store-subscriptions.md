# Event Store Subscriptions

Chronicle.Elixir supports event store subscriptions for importing events from one event store into another event store.

This is useful when you want one Chronicle event store to consume selected events from another store's outbox without writing a reactor or webhook. See [Explicit event store subscriptions](/chronicle/subscriptions/explicit-subscriptions/) and [Outbox/inbox](/chronicle/subscriptions/outbox-inbox/) for the underlying concepts and how they apply across every client. This page adds the Elixir-specific **discoverable subscription module** pattern (`use Chronicle.EventStoreSubscriptions.Subscription`), which isn't covered there.

## Two ways to register subscriptions

You can register subscriptions:

1. **Discoverably** with `use Chronicle.EventStoreSubscriptions.Subscription`
2. **Imperatively** with `Chronicle.EventStoreSubscriptions.subscribe/4`

`Chronicle.Client` can auto-discover and register subscription modules during startup, just like it does for reactors, reducers, read models, migrations, and webhooks.

## Discoverable subscriptions

Define a module like this:

```elixir
defmodule MyApp.EventStoreSubscriptions.DefaultAccountEvents do
  use Chronicle.EventStoreSubscriptions.Subscription,
    source_event_store: "default"

  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

  @impl true
  def define(builder) do
    builder
    |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
    |> DefinitionBuilder.with_event_type(MyApp.Events.FundsDeposited)
  end
end
```

### Options for `use Chronicle.EventStoreSubscriptions.Subscription`

- `:source_event_store` — **required** name of the source event store to subscribe to
- `:id` — optional stable identifier for the subscription. Defaults to the module name.

The `define/1` callback receives a `Chronicle.EventStoreSubscriptions.DefinitionBuilder`.
Return the builder after selecting event types.

If you do not specify any event types, Chronicle.Elixir uses all registered event types available to the client.

## Auto-registration with `Chronicle.Client`

Start `Chronicle.Client` with discovery enabled:

```elixir
children = [
  {Chronicle.Client,
   connection_string: "chronicle://localhost:35000",
   event_store: "target-store",
   otp_app: :my_app}
]
```

If your OTP application includes modules that use `Chronicle.EventStoreSubscriptions.Subscription`, the client discovers them and registers them automatically on startup.

You can also register discoverable subscriptions manually:

```elixir
:ok = Chronicle.register_event_store_subscription(MyApp.EventStoreSubscriptions.DefaultAccountEvents, client: MyApp.Chronicle)

:ok = Chronicle.register_discovered_event_store_subscriptions(client: MyApp.Chronicle)
```

## Imperative registration

For one-off or runtime-defined subscriptions, register them directly:

```elixir
:ok =
  Chronicle.subscribe_to_event_store(
    "default-account-events",
    "default",
    fn builder ->
      builder
      |> Chronicle.EventStoreSubscriptions.DefinitionBuilder.with_event_type(
        MyApp.Events.AccountOpened
      )
      |> Chronicle.EventStoreSubscriptions.DefinitionBuilder.with_event_type(
        MyApp.Events.FundsDeposited
      )
    end
  )
```

The arguments are:

- subscription id
- source event store
- a function that configures the definition builder
- optional keyword options such as `client: MyApp.Chronicle`

## Removing subscriptions

Remove a subscription by identifier:

```elixir
:ok = Chronicle.unsubscribe_from_event_store("default-account-events")
```

## Listing subscriptions

`Chronicle.EventStoreSubscriptions.get_all/1` returns every event store subscription
currently registered with the target event store. Mirrors the C# and Kotlin clients'
`IEventStoreSubscriptions.GetAll()`.

```elixir
{:ok, subscriptions} = Chronicle.EventStoreSubscriptions.get_all()

Enum.each(subscriptions, fn subscription ->
  IO.puts("#{subscription.id} <- #{subscription.source_event_store}")
end)
```

Each subscription is returned as a `%Chronicle.EventStoreSubscriptions.Definition{}` with:

- `:id` — the subscription's identifier
- `:source_event_store` — the event store it imports events from
- `:event_types` — the `%Chronicle.EventStoreSubscriptions.EventType{}` list it subscribes to

## Definition builder

`Chronicle.EventStoreSubscriptions.DefinitionBuilder` currently supports:

- `new/1`
- `with_event_type/2`
- `build/3`

Example:

```elixir
alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

builder =
  DefinitionBuilder.new([MyApp.Events.AccountOpened, MyApp.Events.FundsDeposited])
  |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
```

If `with_event_type/2` is never called, `build/3` uses all registered event types passed to `new/1`.

## Client options

`Chronicle.Client` accepts:

- `:event_store_subscriptions` — explicit list of discoverable subscription modules
- `:discover` — enables or disables auto-discovery
- `:otp_app` — limits discovery to modules that belong to one OTP app

Explicit subscriptions are merged with discovered ones.

## Notes

- Event store subscriptions are registered against the client's target event store.
- The source event store is defined per subscription.
- `:namespace` is accepted in the API option list for consistency with other Chronicle APIs, but it is not currently used by the subscription registration request.
- The current Chronicle contracts expose add/remove operations, so Chronicle.Elixir focuses on registration and removal APIs.
