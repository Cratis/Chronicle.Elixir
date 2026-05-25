# Chronicle Elixir Console Sample

A runnable example demonstrating the Chronicle Elixir client.

## What it does

1. Appends three domain events (`AccountOpened`, `FundsDeposited`, `FundsWithdrawn`) to a Chronicle event store
2. Reacts to those events via a `NotificationReactor` (prints log messages)
3. Projects them into an `Account` read model using model-bound `Chronicle.ReadModel` mappings
4. Also runs a reducer (`AccountReducer`) into `AccountSummary` as an alternative approach
5. Registers a model-bound `unique_event_type` constraint on `AccountOpened`
6. Demonstrates process-scoped identity, correlation id, and causation chain for appends
7. Reads back the projection-backed `Account` model and prints its state
8. Queries event-sequence state (`has_events_for?`, `get_tail_sequence_number`)
9. Lists available event stores and namespaces from the kernel

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
[info] Appending AccountOpened event...
[info] Appending FundsDeposited event...
[info] Appending FundsWithdrawn event...
[info] [Reactor] Account opened: account-384291 for Alice with initial balance 1000
[info] [Reactor] Funds deposited: 500 to account-384291
[info] [Reactor] Funds withdrawn: 200 from account-384291
[info] Reading Account read model...
[info] Event sequence has events for account-384291
[info] Tail sequence number for account-384291: 3
[info] Event stores: ["default"]
[info] Namespaces: ["Default"]
[info] === Account State ===
[info]   ID:           account-384291
[info]   Owner:        Alice
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
      account_opened.ex                    # use Chronicle.EventType
                                           # includes model-bound unique_event_type constraint
      funds_deposited.ex
      funds_withdrawn.ex
    read_models/
      account.ex                           # use Chronicle.ReadModel (projection-backed)
      account_summary.ex                   # reducer-owned read model
    reactors/
      notification_reactor.ex              # use Chronicle.Reactor
    reducers/
      account_reducer.ex                   # use Chronicle.Reducer
                                           # and sequence/store discovery calls in demo flow
```
