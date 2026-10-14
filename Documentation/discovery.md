---
title: Discovery and artifact identity drift
description: See what Chronicle.Elixir discovered at startup, and catch an artifact identity that silently drifted from the kernel.
---

`Chronicle.Client` discovers your event types, reactors, reducers, projections, read models,
constraints, webhooks, event store subscriptions, seeders, migrations, global handlers and
captures at startup — whether through `otp_app:` auto-discovery, loaded-module discovery, or
explicit module lists. This page covers two things that build on that discovery: a report of
what was found, and a check for likely artifact identity drift before registration.

## The discovery report

`Chronicle.Client` builds a `%Chronicle.Discovery.Report{}` during `init/1`, logs a one-line
summary at `:info` and the full report at `:debug`, and exposes it afterwards:

```elixir
report = Chronicle.Client.discovery_report()
Chronicle.Discovery.Report.format(report)
```

```text
Chronicle discovery report:
  event types (2): account-opened (gen 1), funds-deposited (gen 1)
  event sources (0)
  reactors (1): notification-reactor
  reducers (1): account-reducer
  projections (0)
  read models (1): AccountSummary
  constraints (0)
  webhooks (0)
  event store subscriptions (0)
  seeders (0)
  migrations (0)
  global handlers (0)
  captures (0)
```

`Chronicle.Artifacts.report/1` builds the same report directly from an OTP application, without
starting a client — `Chronicle.Artifacts.discover/1` keeps returning its plain map unchanged, so
existing callers are unaffected:

```elixir
report = Chronicle.Artifacts.report(:my_app)
Chronicle.Discovery.Report.count_of(report, :reactor)
```

`mix chronicle.discover --otp-app my_app` prints the same report from the command line — see
below.

## Defaulted ids are a rename hazard

A reactor, reducer or declarative projection with no explicit `:id` defaults it to the module
name (see [Reactors](./reactors.md#pinning-the-id), [Reducers](./reducers.md#pinning-the-id),
[Projections](./projections.md#pinning-the-id)). Renaming or moving that module then changes its
id, and Chronicle treats it as a different artifact — its observation position silently resets.

Discovery warns about this once per module, for the life of the BEAM node (not once per client
start, so it doesn't repeat every time the report is rebuilt):

```text
[warning] MyApp.Reactors.NotificationReactor has no explicit :id and defaults to its module
name. Renaming or moving this module will silently reset its observation position. Pin the id
with `use Chronicle.Reactors.Reactor, id: "...", ...`.
```

Pass `warn_defaulted_ids: false` to `Chronicle.Client` to suppress it.

## Artifact identity drift

Before registering, `Chronicle.Client` can compare what it is about to register with what the
kernel already has, and flag three kinds of drift:

- **`:schema_changed_without_generation`** — an event type generation's schema no longer matches
  what the kernel has recorded for it. Comparison is by coarse shape (property names, nesting,
  and type category), so reordering keys or widening `integer` to `number` isn't drift, but an
  added, removed or retyped field is.
- **`:observer_missing_from_code`** — the kernel has a client-owned reactor, reducer, or
  projection/read-model observer on the `event-log` sequence whose id no longer appears in your
  current code. This finding is always `:info`, for every observer type: an event store can be
  shared by several clients, and the observers another client registered are client-owned too,
  so it is evidence only. It is logged at info level and never fails startup under
  `drift_policy: :fail`. Observers on other event sequences are not compared.
- **`:observer_event_types_changed`** — a still-declared observer's handled event types no longer
  match what the kernel has recorded for it.

Control this with the `:drift_policy` client option:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  otp_app: :my_app,
  drift_policy: :warn}
```

- `:ignore` — skip the check and its kernel calls entirely.
- `:warn` (default) — log any findings and register anyway.
- `:fail` — log findings and refuse to register when a `:warning`-severity finding exists (a
  changed event type schema or a reactor whose handled event types changed). `:info` findings,
  including every `:observer_missing_from_code`, never block registration under any policy. If
  the check itself cannot complete (the kernel is unreachable, an exception, or the 5 second
  deadline passes), `:warn` logs and continues and `:fail` stops — an indeterminate result is
  never treated the same as a clean one. A drift finding under `:fail` is not retried, because
  the same code drifts the same way on every attempt.

The check costs one `AllEventTypes` call, plus one `AllEventTypeGenerations` call for each event
type whose local generation is not the latest the kernel has (a few in parallel). It runs once
per client start; registration retries reuse its result.

:::note[The kernel enforces some of this on its own]
A schema change without a bumped generation is also rejected by the kernel's own
`RegisterEventTypes` validation, independent of `:drift_policy`. `:warn` still reaches that
rejection (and registration still fails, for the kernel's own reason); `:fail` stops first, for
your own reason — useful when you want the clearer, earlier message.
:::

Read the most recent findings at any time:

```elixir
Chronicle.Client.identity_drift()
# => [%Chronicle.Discovery.Drift{kind: :reactor, id: "notification-reactor",
#      reason: :observer_missing_from_code, severity: :info}]
```

## `mix chronicle.discover`

Prints the discovery report from the command line, optionally checking it against a running
kernel:

```bash
mix chronicle.discover --otp-app my_app
mix chronicle.discover --otp-app my_app \
  --connection-string "chronicle://localhost:35000" --fail-on-drift
```

- `--otp-app` — **(required)** the OTP application to discover artifacts from.
- `--connection-string` — compare the report with a kernel's event types and observers (event
  store `"default"`, namespace `"Default"` — the same defaults `Chronicle.Client` uses).
- `--fail-on-drift` — exit `1` when a `:warning`-severity finding exists; has no effect without
  `--connection-string`.

Exit codes: `0` printed cleanly with no drift (or none requested), `1` drift found with
`--fail-on-drift`, `2` could not run (missing `--otp-app`, or the kernel couldn't be reached).
