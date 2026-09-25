---
title: Get started with the Elixir client
description: Add cratis_chronicle to a Mix project, connect to a local development kernel, append an event, and read the projected read model.
---

In this guide you build a small Mix application that records a bank account being opened and reads the account back as a read model. Along the way you learn the three things that trip up most first runs: the development credentials, waiting for the client to finish registering, and the short gap before a projection catches up.

By the end, `iex -S mix` shows your read model coming back from Chronicle:

```text
{:ok, %MyApp.ReadModels.Account{id: "account-1", owner: "Alice", balance: 500}}
```

## Prerequisites

- **Elixir 1.18 or later.** The package declares `~> 1.14`, but its current dependency graph needs more: `grpc 0.11.5` depends on `googleapis 0.1.0`, which requires Elixir `~> 1.18`. CI builds and tests the client with Elixir 1.19.5 on Erlang/OTP 28.5.
- **Docker**, to run the Chronicle development kernel.
- Basic familiarity with Mix projects and supervision trees.

## Start Chronicle

Pull the current development image first, then start it. The client talks to the kernel over gRPC contracts that change between kernel releases, so an old cached image can reject a freshly installed client (see [Troubleshooting](#troubleshooting)).

```shell
docker pull cratis/chronicle:latest-development
docker run -d --name chronicle \
  -p 127.0.0.1:35000:35000 \
  -p 127.0.0.1:27017:27017 \
  cratis/chronicle:latest-development
```

The image bundles MongoDB. The `127.0.0.1:` prefixes publish both ports on this machine only: the development workbench accepts well-known credentials and the bundled MongoDB has no authentication, so keep them off shared networks. Wait until the kernel reports `Healthy`:

```shell
curl --insecure --fail --retry 30 --retry-all-errors --retry-delay 1 https://localhost:35000/health
```

[Run Chronicle locally](/chronicle/get-started/choose-hosting-model/#run-chronicle-locally) covers the other hosting options.

## Install

Create a supervised Mix project:

```shell
mix new my_app --sup
cd my_app
```

Add the client to `deps` in `mix.exs`:

```elixir
defp deps do
  [
    {:cratis_chronicle, "~> 3.5"}
  ]
end
```

Then fetch it:

```shell
mix deps.get
```

`mix deps.get` flags the resolved `grpc 0.11.5` package with published security advisories. The fixed `grpc 1.x` line can't be adopted yet, because the generated `cratis_chronicle_contracts` package requires `grpc ~> 0.11`. Review the advisories against how you deploy the client before you ship it.

## Define an event

An event is a struct that uses `Chronicle.Events.EventType`. The `id:` option is required and is the event type's stable identity, so pick it once and never change it.

```elixir
# lib/my_app/events/account_opened.ex
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened"

  defstruct owner: "", balance: 0
end
```

Give every field a default of the type it holds. The client generates the JSON schema Chronicle validates appends against from these defaults. A field declared as `defstruct [:balance]` has a `nil` default, is registered as a string, and appending an integer to it fails with a schema violation.

## Define a read model

A read model is a struct that uses `Chronicle.ReadModels.ReadModel`. Its `from/2` declarations become a projection that runs inside Chronicle, so you don't write any update code yourself.

```elixir
# lib/my_app/read_models/account.ex
defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", owner: "", balance: 0

  from MyApp.Events.AccountOpened, set: [id: :event_source_id]
end
```

`owner` and `balance` have the same names on the event and the read model, so Chronicle maps them automatically. The only explicit mapping stores the event source id, the account id you append to, in `id`.

:::caution[Multi-word event fields need a camelCase expression in 3.5.0]
Events travel to Chronicle as camelCase JSON, but version 3.5.0 sends atom expressions such as `:owner_name` unchanged. Automatic mapping and atom expressions therefore leave fields like `owner_name` or `initial_balance` empty, without an error. Until that is fixed, map them with the camelCase property name as a string, `set: [owner_name: "ownerName"]`, and use `"$value(true)"` rather than a bare `true` or `false` for a constant.
:::

## Start the client

Add `Chronicle.Client` to your application's supervision tree in `lib/my_app/application.ex`:

```elixir
defmodule MyApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: connection_string(),
       event_store: "my-app",
       otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end

  # Development-only credentials that the local development kernel accepts.
  # Set CHRONICLE_CONNECTION_STRING for any other environment.
  defp connection_string do
    System.get_env(
      "CHRONICLE_CONNECTION_STRING",
      "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000"
    )
  end
end
```

`otp_app: :my_app` tells the client to discover the event types, read models, reactors, reducers and seeders defined in your application. It also creates the `my-app` event store the first time it connects.

The connection string carries the development client id and secret. The development kernel requires an authenticated client, and unlike the .NET client, the Elixir client doesn't fill in these defaults when you leave the credentials out. `chronicle://localhost:35000` on its own connects, but never finishes registering. [Connection strings](connections/connection-strings.md) covers API keys, TLS validation and the other options.

## Wait until the client is registered

The client connects in the background. It first opens a session, then registers your event types, read models and projections, and only then reports itself ready. That takes a few seconds. An append made before the connection is up returns an error instead of waiting, and one made before registration finishes can reach the kernel before your event type is registered:

```elixir
{:error, :not_connected}
```

Wait for the `:registered` phase before your first call:

```elixir
alias Chronicle.Connections.Lifecycle

:ok = Lifecycle.wait_until(Lifecycle.name_for(Chronicle.Client), :registered)
```

`wait_until/3` returns `{:error, :timeout}` if registration doesn't finish within 30 seconds, which is the default. Pass a timeout in milliseconds as the third argument to change it. In a real application, gate the work that needs Chronicle on this call rather than sleeping.

## Append an event

Start an interactive session with your application running:

```shell
iex -S mix
```

Wait for registration, then append:

```elixir
iex> alias Chronicle.Connections.Lifecycle
iex> Lifecycle.wait_until(Lifecycle.name_for(Chronicle.Client), :registered)
:ok
iex> Chronicle.append("account-1", %MyApp.Events.AccountOpened{owner: "Alice", balance: 500})
:ok
```

`"account-1"` is the event source id: the account this fact belongs to. `Chronicle.append/3` returns `:ok` once Chronicle has stored the event, or `{:error, reason}`. The common reasons are:

| Result | Meaning |
|--------|---------|
| `{:error, :not_connected}` | The client isn't connected or registered yet. |
| `{:error, {:constraint_violations, violations}}` | The event failed schema validation or a uniqueness constraint. Each violation has a `Message`. |
| `{:error, {:concurrency_violations, violations}}` | A concurrency scope you passed didn't match the stored events. |
| `{:error, {:incompatible_server, response}}` | The kernel and the resolved contracts package don't match. |

Match on these instead of asserting `:ok` in production code.

## Read it back

Read the account back by its key:

```elixir
iex> Chronicle.read_model(MyApp.ReadModels.Account, "account-1")
{:ok, %MyApp.ReadModels.Account{id: "account-1", owner: "Alice", balance: 500}}
```

Chronicle projects events into read models asynchronously. `:ok` from `append/3` means the event is stored, not that the projection has run, so a read immediately afterwards can still return `{:ok, nil}`. The same `{:ok, nil}` comes back for a key that has no events at all.

When the next step needs the updated read model, you can append with `Chronicle.EventSequences.EventLog.append_and_wait_for_completion/3` instead. It waits, five seconds by default, for every affected observer to catch up:

```elixir
iex> Chronicle.EventSequences.EventLog.append_and_wait_for_completion(
...>   "account-2",
...>   %MyApp.Events.AccountOpened{owner: "Bob", balance: 250}
...> )
{:ok, %{success: true, failed_partitions: []}}
iex> Chronicle.read_model(MyApp.ReadModels.Account, "account-2")
{:ok, %MyApp.ReadModels.Account{id: "account-2", owner: "Bob", balance: 250}}
```

An `{:error, reason}` from this function doesn't always mean the event wasn't stored: the wait itself can fail after a successful append. Don't repeat the append blindly; see [Appending and waiting for observer completion](event-sequences.md#appending-and-waiting-for-observer-completion).

You now have a supervised client appending events and reading a projected read model.

## Troubleshooting

**The client never reaches `:registered`, and the log repeats `Chronicle session dropped: :stream_ended, reconnecting...`.** The connection string has no credentials. Use the development credentials shown above, or the credentials your kernel is configured with.

**Every append returns `{:error, {:incompatible_server, ...}}`.** `mix deps.get` resolved a newer `cratis_chronicle_contracts` than your kernel understands; the response lists the kernel's version. Pull the current `latest-development` image and recreate the container. `cratis_chronicle` accepts any contracts version, and the contracts package reports itself as `0.1.0` locally, so you can't pin it with a version requirement in `mix.exs`. Commit `mix.lock` to keep the resolved contracts version fixed, and move the kernel and the lock file together.

**An append returns `{:error, {:constraint_violations, [...]}}` with `expected string but got number`.** A field on the event has no typed default. Give it one, such as `balance: 0`, and use a new event type id or a fresh event store, because the schema registered for the old id doesn't change.

**The read model is `{:ok, nil}` or has empty fields.** Check, in order: the projection hasn't caught up yet (use `append_and_wait_for_completion/3`); the key you read with is the event source id you appended to; multi-word fields need the camelCase expression described in [Define a read model](#define-a-read-model).

**A call raises `ArgumentError` with `no persistent term stored with this key`.** No client with that name is running. Functions that take a `:client` option look it up by the `name:` the client was started with, which defaults to `Chronicle.Client`.

## Where to next

- [Connections](connections/index.md) for connection strings, TLS, credentials and how the client recovers from dropped connections.
- [Reactors](/chronicle/reactors/getting-started/) to react to events with side effects. The shared guides show Elixir tabs. Reducers don't register in version 3.5.0; see [Reducers](reducers.md).
- [Read models](/chronicle/read-models/) and [Projections](/chronicle/projections/) to query and shape projected state.
- [Constraints](/chronicle/constraints/), [Concurrency](/chronicle/events/concurrency/) and [Transactions](/chronicle/events/transactions/) for append-time rules.
- [Context management](context.md) to record who caused each event and why.
- The [console sample](https://github.com/Cratis/Chronicle.Elixir/tree/main/Samples/console) for a larger, interactive application.
