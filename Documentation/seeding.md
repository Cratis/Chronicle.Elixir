# Seeding

This page shows how to seed events using the Chronicle Elixir client. Seeding is sent to the Chronicle Server when the event store connects, and the server applies it once per namespace. See [Event Seeding](/chronicle/event-seeding/) for the concept this page assumes.

## Define events

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened"

  defstruct [:account_id, :owner_name, :initial_balance]
end

defmodule MyApp.Events.FundsDeposited do
  use Chronicle.Events.EventType, id: "funds-deposited"

  defstruct [:account_id, :amount]
end
```

## Implement a seeder

Use `Chronicle.Seeding.Seeder` and implement the `seed/1` callback:

```elixir
defmodule MyApp.Seeders.AccountSeeder do
  use Chronicle.Seeding.Seeder

  alias MyApp.Events.{AccountOpened, FundsDeposited}

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(AccountOpened, "account-1", [
      %AccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
    ])
  end
end
```

Register it explicitly, or let auto-discovery find it:

```elixir
# Explicit
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000?disableTls=true",
  event_store: "banking",
  seeders: [MyApp.Seeders.AccountSeeder]}

# Auto-discovery (enabled by default when otp_app is set)
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000?disableTls=true",
  event_store: "banking",
  otp_app: :my_app}
```

## Seed multiple events of the same type

`Chronicle.Seeding.for/4` seeds one or more events of the same type for a single event source:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for(AccountOpened, "account-1", [
    %AccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
  ])
  |> Chronicle.Seeding.for(AccountOpened, "account-2", [
    %AccountOpened{account_id: "account-2", owner_name: "Bob", initial_balance: 500}
  ])
end
```

## Seed mixed event types

`Chronicle.Seeding.for_event_source/3` seeds several different event types for the same event source:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for_event_source("account-1", [
    %AccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000},
    %FundsDeposited{account_id: "account-1", amount: 500}
  ])
end
```

## Namespace-scoped seed data

By default, seed data applies to all namespaces in the event store. To target a specific namespace, use `Chronicle.Seeding.for_namespace/3`:

```elixir
def seed(builder) do
  builder
  |> Chronicle.Seeding.for_namespace("production", fn scoped ->
    scoped
    |> Chronicle.Seeding.for(AccountOpened, "account-1", [
      %AccountOpened{account_id: "account-1", owner_name: "Alice", initial_balance: 1000}
    ])
  end)
end
```

The scoped builder supports the same `for/4` and `for_event_source/3` functions as the top-level builder. Each namespace receives only its own scoped events in addition to any global events.

## How it runs

- Seeders are discovered and executed once during `Chronicle.Client` initialization.
- All seeders are invoked, accumulating their events, then all events are sent to Chronicle in a single batch.
- The server deduplicates seeded events and applies them once per namespace.
- Seeders should be idempotent — if your application restarts, seeders run again, and Chronicle's event log handles duplicates based on your event constraints.
- Errors in a seeder are logged but don't prevent other seeders from running or the client from starting.

## Best practices

- Keep seed data minimal and deterministic.
- Use clear event source IDs to make debugging easier.
- Use `:id` on `use Chronicle.Seeding.Seeder` only if you need a stable identifier for tooling — it doesn't affect seeding behavior, since seeders run once per startup rather than being tracked by the server.
- Use `for_namespace/3` when seed data is tenant-specific or environment-specific to avoid polluting other namespaces.
