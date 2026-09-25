---
title: Seeding
description: Define Elixir seeders that append baseline events when the client registers, and understand when seed data is skipped.
---

Seeding gives a fresh event store the events it needs to be useful, such as reference data or demo accounts, without a separate script. This page shows how to seed events with the Chronicle Elixir client. See [Event seeding](/chronicle/event-seeding/) for the concept this page assumes.

The Elixir client seeds from the client side: every time it finishes registering with the kernel, it runs your seeders and appends their events with ordinary appends. That differs from the .NET client, and in version 3.5.0 it re-appends seed data on every run unless you guard it; see [How it runs](#how-it-runs).

## Define events

```elixir
defmodule MyApp.Events.SeededAccountOpened do
  use Chronicle.Events.EventType, id: "seeding-account-opened"

  defstruct account_id: "", owner_name: "", initial_balance: 0
end

defmodule MyApp.Events.SeededFundsDeposited do
  use Chronicle.Events.EventType, id: "seeding-funds-deposited"

  defstruct account_id: "", amount: 0
end
```

Give every field a typed default: the client builds the event's JSON schema from the defaults, and a `nil` default registers the field as a string.

## Implement a seeder

Use `Chronicle.Seeding.Seeder` and implement the `seed/1` callback:

```elixir
defmodule MyApp.Seeders.AccountSeeder do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.SeededAccountOpened

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(SeededAccountOpened, "account-1", [
      %SeededAccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
    ])
  end
end
```

`seed/1` returns the builder. Register the seeder explicitly, or let discovery find it:

```elixir
# Explicit
{Chronicle.Client,
  connection_string: connection_string,
  event_store: "banking",
  seeders: [MyApp.Seeders.AccountSeeder]}

# Discovery: finds every module in :my_app that uses Chronicle.Seeding.Seeder
{Chronicle.Client,
  connection_string: connection_string,
  event_store: "banking",
  otp_app: :my_app}
```

## Seed multiple events of the same type

`Chronicle.Seeding.for/4` seeds one or more events of the same type for a single event source:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for(SeededAccountOpened, "account-1", [
    %SeededAccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
  ])
  |> Chronicle.Seeding.for(SeededAccountOpened, "account-2", [
    %SeededAccountOpened{account_id: "account-2", owner_name: "Bob", initial_balance: 500}
  ])
end
```

## Seed mixed event types

`Chronicle.Seeding.for_event_source/3` seeds several different event types for the same event source:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for_event_source("account-1", [
    %SeededAccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000},
    %MyApp.Events.SeededFundsDeposited{account_id: "account-1", amount: 500}
  ])
end
```

## Namespace-scoped seed data

Seed data without a namespace goes to the namespace the client is configured with, the `:namespace` option on `Chronicle.Client`, which defaults to `"Default"`. It isn't copied to other namespaces. To target a specific namespace, use `Chronicle.Seeding.for_namespace/3`:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for_namespace("tenant-a", fn scoped ->
    scoped
    |> Chronicle.Seeding.for(SeededAccountOpened, "account-1", [
      %SeededAccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
    ])
  end)
end
```

The scoped builder supports the same `for/4` and `for_event_source/3` functions as the top-level builder.

## How it runs

- Seeders run each time the client reaches the `:registered` phase: at startup, and again after every reconnect. See [Resilience](connections/resilience.md).
- Every seeder's `seed/1` runs first, accumulating events. A seeder that raises is logged with `Failed to execute seeder` and skipped; the others still run.
- The client then groups the events by namespace and event source id, and appends each group with one `append_many` call, which is atomic for that event source. It is designed to skip a group whose event source already has events.
- If an append fails, for example because the kernel rejects an event, seeding stops, logs `Seeding failed`, and runs again from the start five seconds later.

:::danger[Seed data is appended again on every run in 3.5.0]
The skip check uses `Chronicle.has_events_for?/2`, which always returns `{:ok, false}` in version 3.5.0. The client therefore appends every seeded event again each time it starts or reconnects, and a seeded event source collects duplicate events.

Until that is fixed, guard each event source inside `seed/1` by reading its events first:

```elixir
defmodule MyApp.Seeders.AccountSeeder do
  use Chronicle.Seeding.Seeder

  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.SeededAccountOpened

  @impl true
  def seed(builder) do
    case EventLog.get_for_event_source("account-1",
           client: builder.client,
           namespace: builder.namespace
         ) do
      {:ok, []} ->
        Chronicle.Seeding.for(builder, SeededAccountOpened, "account-1", [
          %SeededAccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
        ])

      _already_seeded_or_error ->
        builder
    end
  end
end
```

Passing `client:` and `namespace:` from the builder makes the check read the same client and namespace the seed events are written to; use the target namespace instead for data inside `for_namespace/3`. Skipping on `{:error, _}` means a failed read seeds nothing on that run instead of risking a duplicate.

The guard reads and then appends in two steps, so it only prevents duplicates from one writer at a time. If several application instances can start together against the same event store, seed from one of them, or let a [unique constraint](/chronicle/constraints/) reject the second copy.
:::

Because seeding works per event source, editing a seeder for an event source that already has events doesn't change the stored events. To correct seed data that is already stored, append correcting events yourself, or seed a fresh event store.

## Best practices

- Keep seed data minimal and deterministic, with fixed event source ids, so a guard can recognize data that is already there.
- Give each seeded event source its complete set of events in one seeder run.
- Use typed defaults on seeded event types, just like any other event. A schema violation stops seeding and retries it every five seconds.
- Use the `:id` option on `use Chronicle.Seeding.Seeder` only if you need a stable identifier for tooling. The client doesn't send it to Chronicle.
- Use `for_namespace/3` when seed data is tenant-specific or environment-specific.
