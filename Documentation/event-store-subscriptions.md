---
title: Event store subscriptions
description: Import selected events from another event store's outbox into yours using discoverable modules or imperative Elixir event store subscriptions.
---

Chronicle.Elixir supports event store subscriptions for importing events from one event store into another event store.

This is useful when you want one Chronicle event store to consume selected events from another store's outbox without writing a reactor or webhook. See [Explicit event store subscriptions](/chronicle/subscriptions/explicit-subscriptions/) and [Outbox/inbox](/chronicle/subscriptions/outbox-inbox/) for the underlying concepts and how they apply across every client. This page adds the Elixir-specific **discoverable subscription module** pattern (`use Cratis.Chronicle.EventStoreSubscriptions.Subscription`), which isn't covered there.

The registration, listing and removal requests below target the selected client's event store, not a namespace.
Confirm the source/target stores and selected event types before registering or removing anything.

## Notes

- Event store subscriptions are registered against the client's target event store.
- The source event store is defined per subscription.
- `:namespace` is accepted in the API option list for consistency with other Chronicle APIs, but it is not currently used by the subscription registration request.
- The client can add, remove and list subscriptions. There is no separate update call.

## Two ways to register subscriptions

Choose one registration approach for a subscription:

1. **Discoverably** with `use Cratis.Chronicle.EventStoreSubscriptions.Subscription`
2. **Imperatively** with `Cratis.Chronicle.EventStoreSubscriptions.subscribe/4`

`Cratis.Chronicle.Client` can auto-discover and register subscription modules during startup, just like it does for reactors, reducers, read models, migrations, and webhooks.

## Discoverable subscriptions

This module explicitly selects the two event types shown below.

If you don't select any event types, the subscription uses the event types the client was given in `:event_types` or discovered in your application. When that list is empty, for example with `discover: false` and no `:event_types`, it falls back to every event type module loaded in the VM. Select event types explicitly to control exactly what the subscription receives.

```elixir
defmodule MyApp.EventStoreSubscriptions.DefaultAccountEvents do
  use Cratis.Chronicle.EventStoreSubscriptions.Subscription,
    source_event_store: "default"

  alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder

  @impl true
  def define(builder) do
    builder
    |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
    |> DefinitionBuilder.with_event_type(MyApp.Events.FundsDeposited)
  end
end
```

### Options for `use Cratis.Chronicle.EventStoreSubscriptions.Subscription`

- `:source_event_store` — **required** name of the source event store to subscribe to
- `:id` — optional stable identifier for the subscription. Defaults to the module name.

The `define/1` callback receives a `Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder`.
Return the builder after selecting event types.

## Auto-registration with `Cratis.Chronicle.Client`

Start `Cratis.Chronicle.Client` with discovery enabled:

```elixir
children = [
  {Cratis.Chronicle.Client,
   connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
   event_store: "target-store",
   otp_app: :my_app}
]
```

If your OTP application includes modules that use `Cratis.Chronicle.EventStoreSubscriptions.Subscription`, the client discovers them and registers them automatically on startup.

You can also register discoverable subscriptions manually:

```elixir
:ok = Cratis.Chronicle.register_event_store_subscription(MyApp.EventStoreSubscriptions.DefaultAccountEvents)

:ok = Cratis.Chronicle.register_discovered_event_store_subscriptions()
```

Both accept `client:` with the `name:` of another running client, when you start more than one.

## Imperative registration

For one-off or runtime-defined subscriptions, register them directly:

```elixir
:ok =
  Cratis.Chronicle.subscribe_to_event_store(
    "default-account-events",
    "default",
    fn builder ->
      builder
      |> Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder.with_event_type(
        MyApp.Events.AccountOpened
      )
      |> Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder.with_event_type(
        MyApp.Events.FundsDeposited
      )
    end
  )
```

The arguments are:

- subscription id
- source event store
- a function that configures the definition builder
- optional keyword options, such as `client:` with the name of a non-default client

## Listing subscriptions

`Cratis.Chronicle.EventStoreSubscriptions.get_all/1` returns every event store subscription
currently registered with the target event store. Mirrors the C# and Kotlin clients'
`IEventStoreSubscriptions.GetAll()`.

```elixir
{:ok, subscriptions} = Cratis.Chronicle.EventStoreSubscriptions.get_all()

Enum.each(subscriptions, fn subscription ->
  IO.puts("#{subscription.id} <- #{subscription.source_event_store}")
end)
```

Each subscription is returned as a `%Cratis.Chronicle.EventStoreSubscriptions.Definition{}` with:

- `:id` — the subscription's identifier
- `:source_event_store` — the event store it imports events from
- `:event_types` — the `%Cratis.Chronicle.EventStoreSubscriptions.EventType{}` list it subscribes to

## Removing subscriptions

Confirm the subscription id, target event store and authority from inspection before removing it.

Remove a subscription by identifier:

```elixir
:ok = Cratis.Chronicle.unsubscribe_from_event_store("default-account-events")
```

## Definition builder

`Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder` currently supports:

- `new/1`
- `with_event_type/2`
- `build/3`

Example:

```elixir
alias Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder

builder =
  DefinitionBuilder.new([MyApp.Events.AccountOpened, MyApp.Events.FundsDeposited])
  |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
```

If `with_event_type/2` is never called, `build/3` uses all registered event types passed to `new/1`.

## Client options

`Cratis.Chronicle.Client` accepts:

- `:event_store_subscriptions` — explicit list of discoverable subscription modules
- `:discover` — enables or disables auto-discovery
- `:otp_app` — limits discovery to modules that belong to one OTP app

Explicit subscriptions are merged with discovered ones.
