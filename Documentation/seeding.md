---
title: Seeding
description: Define Elixir seeders that append baseline events when the client registers, and understand when seed data is skipped.
---

Seeding gives a fresh event store the events it needs to be useful, such as reference data or demo accounts, without a separate script. This page shows how to seed events with the Chronicle Elixir client. See [Event seeding](/chronicle/event-seeding/) for the concept this page assumes.

Every time the client finishes registering with the kernel it runs your seeders and hands their entries to the kernel's seeding service, exactly as the .NET client does. The kernel tracks which entries it has applied, so running again is safe and only new entries are applied; see [How it runs](#how-it-runs).

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
- Every seeder's `seed/1` runs first, accumulating entries. A seeder that raises is logged as an error and contributes **none** of its entries (a seeder is applied whole or not at all); the other seeders still run.
- The client groups the entries by namespace, event type and event source and sends them in one request to the kernel's seeding service. Event type tags (`use Chronicle.Events.EventType, tags: [...]`) travel with each entry.
- The kernel remembers which entries it has applied, by event source, event type, content and tags. **An entry you add later to an event source that was seeded before is applied; an entry that was applied is not applied again.** Entries without `for_namespace/3` are global: the kernel applies them to every namespace it knows about.
- If the request fails, for example because the kernel rejects an event, seeding logs `Seeding failed` and runs again from the start five seconds later.

Because the kernel does the bookkeeping, it is safe for several application instances to start together. Editing the *content* of an entry that was already applied is a new entry: the old event stays. To correct stored seed data, append correcting events yourself.

## Best practices

- Keep seed data minimal and deterministic, with fixed event source ids and content, so reruns apply nothing.
- You can add entries to an already seeded event source later; only the new entries are applied.
- Use typed defaults on seeded event types, just like any other event. A schema violation fails the request and seeding retries every five seconds.
- Use the `:id` option on `use Chronicle.Seeding.Seeder` only if you need a stable identifier for tooling. The client doesn't send it to Chronicle.
- Use `for_namespace/3` when seed data is tenant-specific or environment-specific.
