# Chronicle Elixir Console Sample

A runnable example demonstrating the Chronicle Elixir client.

## What it does

1. Appends a legacy generation 1 `LegacyAccountOpened` event plus `FundsDeposited` and `FundsWithdrawn`
2. Registers `ConsoleSample.Migrations.AccountOpenedV2Migration` and lets Chronicle upcast the legacy event into generation 2 `AccountOpened`
3. Uses `Chronicle.Events.ConcurrencyScope` with a unit of work for the deposit and withdrawal batch
4. Reacts to those events via a `NotificationReactor` (prints log messages)
5. Projects them into an `Account` read model using model-bound `Chronicle.ReadModel` mappings
6. Also runs a reducer (`AccountReducer`) into `AccountSummary` as an alternative approach
7. Registers a model-bound `unique_event_type` constraint on `AccountOpened`
8. Demonstrates process-scoped identity, correlation id, causation chain, and optimistic concurrency for appends
9. Auto-discovers an event store subscription from the `default` event store
10. Imperatively registers and removes a second event store subscription during the demo
11. Exercises the full `Chronicle.ReadModels` query surface: `get`, `get_instance_by_id`, `all`, `get_instances`, `query`, `get_snapshots_by_id`, `occurrences`, and `definitions`
12. Reads back the projection-backed `Account` model and prints migrated state, including `account_tier`
13. Queries event-sequence state (`has_events_for?`, `get_tail_sequence_number`)
14. Lists available event stores, namespaces, webhooks, and jobs from the kernel

## Prerequisites

- Elixir 1.14+ and OTP 25+
- A Chronicle kernel running on `localhost:35000`

> **Tip:** The easiest way to run Chronicle locally is via Docker:
> ```shell
> docker run -p 35000:35000 -p 8080:8080 cratis/chronicle:latest-development
> ```

## Running

```shell
cd Samples/console
mix deps.get
mix run --no-halt
```

You should see output similar to:

```
[info] === Chronicle Elixir Console Sample ===
[info] Using account ID: account-384291
[info] Appending LegacyAccountOpened generation 1 event...
[info] Chronicle should upcast it to AccountOpened generation 2 with account_tier="standard".
[info] Building concurrency scope from tail sequence number 1...
[info] Buffering FundsDeposited and FundsWithdrawn in a unit of work...
[info] Committing unit of work ... with buffered events...
[info] [Reactor] Account opened: account-384291 for Alice with initial balance 1000 and tier standard
[info] [Reactor] Funds deposited: 500 to account-384291
[info] [Reactor] Funds withdrawn: 200 from account-384291
[info] Reading Account read model...
[info] Showcasing Chronicle.ReadModels query APIs...
[info] ReadModels.get_instance_by_id/3 returned account-384291 with balance 1300
[info] ReadModels.query/2 returned page 1 with 1 item(s) out of 1
[info] ReadModels.get_snapshots_by_id/3 returned 3 snapshot(s)
[info] ReadModels.definitions/1 returned 2 definition(s); sample models: [{"Account", :projection}, {"AccountSummary", :reducer}]
[info] Event sequence has events for account-384291
[info] Tail sequence number for account-384291: 3
[info] Event stores: ["default"]
[info] Namespaces: ["Default"]
[info] Auto-discovered event store subscriptions are registered during Chronicle.Client startup.
[info] Registering an imperative event store subscription from the default store...
[info] Registered event store subscription console-sample-default-deposits
[info] Removed event store subscription console-sample-default-deposits
[info] === Account (projection) ===
[info]   ID:           account-384291
[info]   Owner:        Alice
[info]   Tier:         standard
[info]   Balance:      1300
[info]   Transactions: 2
[info] === Demo complete ===
```

## Configuration

Override the Chronicle connection string via environment variable:

```shell
CHRONICLE_CONNECTION_STRING="chronicle://myserver:35000?apiKey=secret" mix run --no-halt
```

## Project structure

```
lib/
  console_sample.ex                        # Demo scenario
  console_sample/
    application.ex                         # OTP Application (starts Chronicle.Client with auto-discovery)
    events/
      account_opened.ex                    # generation 2 current event type
      legacy_account_opened.ex             # generation 1 legacy event type used in the demo
      funds_deposited.ex
      funds_withdrawn.ex
    migrations/
      account_opened_v2_migration.ex       # use Chronicle.Events.Migration
    read_models/
      account.ex                           # use Chronicle.ReadModel (projection-backed)
      account_summary.ex                   # reducer-owned read model
    reactors/
      notification_reactor.ex              # use Chronicle.Reactor
    reducers/
      account_reducer.ex                   # use Chronicle.Reducer
    event_store_subscriptions/
      default_account_events.ex            # use Chronicle.EventStoreSubscriptions.Subscription
                                           # and sequence/store discovery calls in demo flow
```

The sample relies on `Chronicle.Client` auto-discovery, so the migration,
reactor, reducer, read model, and event store subscription modules are picked
up automatically when the application starts. During the demo, `ConsoleSample`
also queries both the projection-backed `Account` read model and the reducer-
backed `AccountSummary` read model through `Chronicle.ReadModels`.
