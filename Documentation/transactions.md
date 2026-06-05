# Transactions and Unit of Work

Chronicle.Elixir supports client-side transactions through `Chronicle.Transactions.UnitOfWork`.
A unit of work buffers event appends locally and flushes them with a single Chronicle `append_many`
operation when you commit.

## When to use transactions

Use a unit of work when one logical operation needs to emit multiple events and you want:

- One shared correlation id across the buffered appends
- One commit point
- No network I/O until the operation is ready to complete
- Transaction-aware appends through `Chronicle.append/3`, `Chronicle.append_many/3`, or a transactional event sequence

## Basic usage

```elixir
alias Chronicle.Transactions.UnitOfWork
alias MyApp.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}

unit_of_work = UnitOfWork.begin()

:ok = Chronicle.append("account-42", %AccountOpened{account_id: "account-42", owner_name: "Alice"})
:ok = Chronicle.append("account-42", %FundsDeposited{account_id: "account-42", amount: 500})
:ok = Chronicle.append("account-42", %FundsWithdrawn{account_id: "account-42", amount: 200})

:ok = UnitOfWork.commit(unit_of_work)
```

While the unit of work is active, those appends are buffered in memory. Chronicle only receives them when `commit/1` runs.

## Using the convenience API

```elixir
Chronicle.with_unit_of_work(fn _unit_of_work ->
  :ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})
  :ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})
end)
```

If the callback raises, the unit of work is rolled back automatically.

## Reading the current unit of work

```elixir
unit_of_work = Chronicle.begin_unit_of_work()
current = Chronicle.current_unit_of_work()

current == unit_of_work
# => true
```

You can also inspect the correlation id that belongs to the transaction:

```elixir
correlation_id = Chronicle.Transactions.UnitOfWork.correlation_id(unit_of_work)
```

## Event log integration

`Chronicle.EventLog` is transaction-aware.
If a unit of work is active, these calls buffer instead of writing immediately:

- `Chronicle.append/3`
- `Chronicle.append_many/3`
- `Chronicle.EventLog.append/3`
- `Chronicle.EventLog.append_many/3`

The buffered events keep their event source id, stream metadata, tags, subject, identity, causation,
and optional concurrency scope until commit time.

## Custom event sequences

Use `Chronicle.event_sequence/2` to work with a non-default event sequence.
Call `transactional/1` to get a transaction-aware wrapper.

```elixir
alias Chronicle.EventSequences.EventSequence
alias Chronicle.EventSequences.TransactionalEventSequence
alias Chronicle.Transactions.UnitOfWork

unit_of_work = UnitOfWork.begin()

sequence =
  Chronicle.event_sequence("audit-sequence")
  |> EventSequence.transactional()

:ok =
  TransactionalEventSequence.append(
    sequence,
    "account-42",
    %MyApp.Events.AuditEntry{message: "account opened"}
  )

:ok = UnitOfWork.commit(unit_of_work)
```

## Commit, rollback, and completion state

```elixir
unit_of_work = Chronicle.Transactions.UnitOfWork.begin()

Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})

Chronicle.Transactions.UnitOfWork.is_completed?(unit_of_work)
# => false

:ok = Chronicle.Transactions.UnitOfWork.commit(unit_of_work)

Chronicle.Transactions.UnitOfWork.is_completed?(unit_of_work)
# => true
Chronicle.Transactions.UnitOfWork.is_success?(unit_of_work)
# => true
```

To discard buffered events, roll the unit of work back:

```elixir
:ok = Chronicle.Transactions.UnitOfWork.rollback(unit_of_work)
```

You can register completion callbacks with `on_completed/2`.
The callback runs on both commit and rollback.

## Constraints and errors

A committed unit of work reports the same Chronicle append failures as direct appends:

- `{:constraint_violations, violations}`
- `{:append_errors, errors}`

When a unit of work has already completed, Chronicle raises:

- `Chronicle.Transactions.UnitOfWorkIsAlreadyCommitted`
- `Chronicle.Transactions.UnitOfWorkIsAlreadyRolledBack`

If you try to use transaction-only APIs without starting a unit of work, Chronicle raises:

- `Chronicle.Transactions.NoUnitOfWorkStarted`

## Important behavior

### One event sequence per unit of work

Chronicle.Elixir commits a unit of work through a single Chronicle `append_many` request.
Because of that, a unit of work currently targets exactly one event sequence, one client, and one namespace.
Trying to buffer events for a different event sequence in the same unit of work raises an `ArgumentError`.

### Correlation, identity, and causation

The unit of work has its own correlation id. Buffered appends inherit identity and causation metadata from the
process context at the time they are added, and the commit uses the unit of work correlation id.

### Concurrency scopes

Concurrency scopes are preserved while events are buffered. On commit, Chronicle sends them with the buffered batch
so optimistic concurrency checks still apply.
