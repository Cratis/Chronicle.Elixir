---
title: Testing
description: Test commands, reactors, reducers, constraints and concurrency against an in-memory kernel, and assert on what was appended.
---

Start with the [ExUnit Case and assertion](#assertions); adapt these excerpts to your application's event/model modules.
Read the [modeled-kernel limits](#what-runs-for-real-and-what-is-modeled) before choosing manual setup, projection evaluation, facade mocking or a real-kernel integration test.
These are alternatives for different tasks, not a script to run in order.

## What runs for real, and what is modeled

Registration, appends and reads go through the real client code against
`Cratis.Chronicle.Testing.InMemoryKernel`, which answers the compatibility check,
`Append`/`AppendManyForEventSources`, reads, `TailSequenceNumber`,
`HasEventsForEventSourceId`, and the registration calls. Concurrency scopes are
honored along every dimension, including `expecting_no_matching_event/1`.
Constraints support `unique/2` (scoped, case-insensitive, respecting removal) and
`unique_event_type/1`. Every other RPC — most prominently `closes_stream`
constraints, and the real `ReadModels`/`Projections` query surface — returns
`{:error, {:not_supported_in_memory, rpc}}`.

Reactors and reducers do not run through a real gRPC observation stream (the
in-memory kernel does not simulate bidirectional streaming): a
`Cratis.Chronicle.Testing.Dispatcher` process runs them synchronously, right after each
committed append, by calling the same dispatch logic the real stream handlers use.
A reactor's own side-effect append runs through the real client again, in this
dispatcher process — never inside the kernel's own process, so it can never
deadlock it.

## Scenarios

A **scenario** states one behavior in the shape of a Specification: facts are given, the behavior happens **once**, and each `test` is one `should_*` expectation. `Cratis.Chronicle.Testing.EventScenario` (events and their constraints), `Cratis.Chronicle.Testing.ReadModelScenario` (projections and reducers) and `Cratis.Chronicle.Testing.ReactorScenario` (reactors) run against the in-memory kernel.

```elixir
defmodule MyApp.Accounts.ForAccountOpened.WhenOpeningTwice do
  use Cratis.Chronicle.Testing.EventScenario,
    event_types: [MyApp.Accounts.AccountOpened]

  alias MyApp.Accounts.AccountOpened

  setup_all %{scenario: scenario} do
    scenario =
      scenario
      |> given_events("account-1", %AccountOpened{owner: "Ada"})
      |> append("account-1", %AccountOpened{owner: "Ada"})

    %{scenario: scenario}
  end

  test "should be refused by the constraint", %{scenario: scenario} do
    should_have_constraint_violation(scenario, "account-opened-once")
  end

  test "should keep only the first event", %{scenario: scenario} do
    should_have_tail_sequence_number(scenario, 0)
  end
end
```

`use` starts the kernel once for the module (`lifecycle: :shared`, the default) and puts the scenario in the context as `:scenario`; `lifecycle: :per_test` starts one per test, and you write `setup` instead of `setup_all`. Every option of `start_supervised_client/1` is accepted. A scenario is an immutable value: **given** and **because** functions return the next scenario, and **should** functions return the scenario they checked, so they chain.

| Scenario | Given and because | Should |
| --- | --- | --- |
| `EventScenario` | `given_events/3`, `append/3,4` | `should_be_successful/1`, `should_have_constraint_violation/1,2`, `should_have_concurrency_violation/1`, `should_have_appended/2,3`, `should_not_have_appended/2,3`, `should_have_appended_exactly/2`, `should_not_have_appended_any_events/1`, `should_have_tail_sequence_number/2`, `should_not_have_observer_failures/1` |
| `ReadModelScenario` | `given_events/3` | `should_have_read_model/4` (a struct, a sub-map or a predicate), `should_not_have_read_model/3`; `read_model/3` returns it |
| `ReactorScenario` | `given_events/3`, `append/3,4` | the appended `should_*` of `EventScenario`, and `should_have_observer_failures/1,2` |

Only the events appended by `append/3,4`, and by the reactors it triggered, count for the `should_have_appended` family; the given events do not. A read model built by a projection is evaluated in memory (the subset in [Evaluating a projection read model in memory](#evaluating-a-projection-read-model-in-memory)); one built by a reducer is the one the kernel's observers keep. Both are asked for by module and key.

Name a spec for what it specifies, not with a `_test` suffix: `for_<unit>/when_<behavior>/<and|with|without>_<condition>.exs`, beside the code, as in the C# and TypeScript specs. They are scripts, so a release never contains them. Point `mix test` at the folders:

```elixir
test_paths: ["lib"],
test_load_filters: [&(String.contains?(&1, "/for_") and not String.contains?(&1, "/given/"))],
```

For commands and queries, [Arc for Elixir](https://github.com/Cratis/Arc.Elixir) has `CommandScenario` and `QueryScenario`, and `Cratis.Arc.Test.Should` for the `should_*` assertions on any value.

## Assertions

Prefer `Cratis.Chronicle.Testing.Case` in ExUnit, which handles client setup and teardown for
you and is safe under `async: true`:

```elixir
defmodule MyApp.AccountTest do
  use Cratis.Chronicle.Testing.Case,
    event_types: [MyApp.Events.AccountOpened],
    reducers: [MyApp.Reducers.AccountReducer]

  import Cratis.Chronicle.Testing.Assertions

  test "opening an account appends AccountOpened", %{chronicle: client} do
    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        "account-1",
        %MyApp.Events.AccountOpened{owner_name: "Alice", initial_balance: 100},
        client: client
      )

    assert_appended(client, MyApp.Events.AccountOpened, event_source_id: "account-1")
  end
end
```

`Cratis.Chronicle.Testing.Assertions` asserts on appended events and on the structured
rejections `Cratis.Chronicle.EventSequences.EventLog` returns:

```elixir
import Cratis.Chronicle.Testing.Assertions

assert_appended(client, %AccountOpened{owner_name: "Alice", initial_balance: 100},
  event_source_id: "account-1"
)

assert_appended(client, FundsDeposited, event_source_id: "account-1", count: 1)
refute_appended(client, AccountClosed, event_source_id: "account-1")

result = Cratis.Chronicle.EventSequences.EventLog.append("user-2", %UserRegistered{email: "taken@example.com"}, client: client)
assert_constraint_violation(result, "UniqueEmail")
```

A matcher is an exact event struct (compared with `==`), an event type module (any
event of that type), or a 1-arity predicate function.

## Start a client against an in-memory kernel

`Cratis.Chronicle.Testing.start_supervised_client/1` boots a real `Cratis.Chronicle.Client` pointed
at `Cratis.Chronicle.Testing.InMemoryKernel` instead of a socket. Appends, constraints,
concurrency scopes and unit-of-work all run through the real client code — only the
transport is fake.

```elixir
{:ok, client} =
  Cratis.Chronicle.Testing.start_supervised_client(
    event_types: [MyApp.Events.AccountOpened, MyApp.Events.FundsDeposited],
    reducers: [MyApp.Reducers.AccountReducer],
    reactors: [MyApp.Reactors.WelcomeReactor]
  )

:ok =
  Cratis.Chronicle.EventSequences.EventLog.append(
    "account-1",
    %MyApp.Events.AccountOpened{owner_name: "Alice", initial_balance: 100},
    client: client
  )

Cratis.Chronicle.Testing.stop_supervised_client(client)
```

## Waiting for reactors and reducers

An append returns as soon as the event is committed; reactors and reducers run
afterward. `Cratis.Chronicle.Testing.wait_for_observers/1` is a deterministic,
sleep-free barrier — it blocks until every batch appended so far has been
processed:

```elixir
:ok = Cratis.Chronicle.EventSequences.EventLog.append("account-1", %FundsDeposited{amount: 25}, client: client)
:ok = Cratis.Chronicle.Testing.wait_for_observers(client)

{:ok, %AccountReadModel{balance: 125}} =
  Cratis.Chronicle.Testing.read_model(client, MyApp.Reducers.AccountReducer, "account-1")
```

It returns `{:error, failures}` when a reactor or reducer raised while processing
an event.

## Reading reducer state and raw events

`Cratis.Chronicle.Testing.read_model/3` reads the read model state a reducer built, keyed
by event source id — there is no in-memory `ReadModels` query surface to read it
through. `Cratis.Chronicle.Testing.appended_events/2` returns every event appended for an
event source, decoded into `Cratis.Chronicle.Events.AppendedEvent` structs.

## Evaluating a projection read model in memory

`Cratis.Chronicle.Testing.Projections` evaluates the supported subset of a
`Cratis.Chronicle.ReadModels.ReadModel`'s embedded declarations — `from/2` (`:set`,
`:set_once`, `:add`, `:subtract`, `:count`, `:increment`, `:decrement`, `:remove`,
`:clear`, auto-map) and `removed_with/2` — against a single event, without a kernel.
Dictionary entries keyed by `{:event_content, property}` are evaluated; keys and
values that need the event context (`{:event_context, _}`, `{:caused_by, _}`) raise
`Cratis.Chronicle.Testing.UnsupportedProjectionOperation`, because `apply_event/4` has no
event context:

`join/2`, `children/2`, `from_every/1` and `removed_with_join/2` need the
server-side projection engine and raise
`Cratis.Chronicle.Testing.UnsupportedProjectionOperation` — use
`Cratis.Chronicle.Testing.Integration` against a real kernel for those.

```elixir
{:ok, account} = Cratis.Chronicle.Testing.Projections.apply_event(AccountReadModel, nil, %AccountOpened{...})
{:ok, account} = Cratis.Chronicle.Testing.Projections.apply_event(AccountReadModel, account, %FundsDeposited{amount: 25})
```

## Mocking the `Chronicle` facade

`Chronicle` adopts `Cratis.Chronicle.Behaviour`, so code that only needs to be observed
calling the facade with the right arguments can mock it with
[Mox](https://hex.pm/packages/mox) (not a dependency of this library):

```elixir
Mox.defmock(MyApp.ChronicleMock, for: Cratis.Chronicle.Behaviour)
Mox.expect(MyApp.ChronicleMock, :append, fn "account-1", %AccountOpened{}, _opts -> :ok end)
```

Prefer `Cratis.Chronicle.Testing.start_supervised_client/1` when the behavior under test
should see real appends, reactors, reducers, constraints and concurrency checks.

## Integration tests against a real kernel

`Cratis.Chronicle.Testing.Integration.setup_isolated_client/2` starts a real
`Cratis.Chronicle.Client` against a running kernel (read from
`CHRONICLE_INTEGRATION_CONNECTION_STRING` by default), with a unique event store
and namespace so the test never collides with another test's events:

The event store and namespace are not removed afterward; read the cleanup limitation below before running this example.

```elixir
@moduletag :integration

setup do
  Cratis.Chronicle.Testing.Integration.setup_isolated_client(
    event_types: [MyApp.Events.AccountOpened],
    reducers: [MyApp.Reducers.AccountReducer]
  )
end

test "appends and projects", %{chronicle: client} do
  {:ok, result} =
    Cratis.Chronicle.EventSequences.EventLog.append_with_result("account-1", %AccountOpened{}, client: client)

  :ok = Cratis.Chronicle.Testing.Integration.wait_for_observers(result.sequence_number, client: client)
end
```

`wait_for_observers/2` delegates to
`Cratis.Chronicle.EventSequences.EventLog.wait_for_sequence_number/2` — no sleeps.
Removing the event store and namespace afterward is not possible yet: see
[Limits and gaps](limits-and-gaps.md).
