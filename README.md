# Chronicle Elixir Client

Event sourcing for Elixir — the idiomatic client for [Cratis Chronicle](https://github.com/Cratis/Chronicle), the open-source (MIT) event-sourcing database and processing runtime.

[![Hex.pm](https://img.shields.io/hexpm/v/cratis_chronicle.svg)](https://hex.pm/packages/cratis_chronicle)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/cratis_chronicle)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

`cratis_chronicle` brings event sourcing and CQRS to Elixir applications: append events to an event store, project them into read models, and react to them — all backed by the Chronicle Kernel. It builds on Chronicle's language-agnostic gRPC API and exposes OTP-native constructs including:

- **`use Chronicle.Events.EventType`** — annotate structs as event types with stable IDs
- **`use Chronicle.ReadModels.ReadModel`** — declare model-bound projections executed server-side
- **`use Chronicle.Reactors.Reactor`** — react to events with side effects
- **`use Chronicle.Reducers.Reducer`** — fold events into read models in your own process
- **`use Chronicle.Seeding.Seeder`** — seed event stores with baseline events at startup
- **Model-bound constraints** — unique and unique-event-type constraints on event types
- **Context-aware appends** — process-scoped identity, correlation, and causation metadata
- **Optimistic concurrency** — guard appends with scoped tail-sequence checks
- **Transactions** — buffer and commit multi-event units of work
- **Jobs and webhooks** — inspect Chronicle jobs and manage webhook registrations
- **Resilient connection** — automatic reconnection with exponential backoff

We believe event sourcing is worth it for almost any system dealing with information and business flows — and that in Elixir it should feel like Elixir: modules, structs, and `use` macros rather than a foreign paradigm. The client is designed to keep friction and boilerplate low, so it reads as familiar code even if you have never event-sourced before. It is part of one deliberately simple Cratis ecosystem, built with productivity, quality, and reliability in mind — AI-friendly by design, with free [AI skills](https://github.com/Cratis/AI) for building with the stack.

## Install

Add `cratis_chronicle` to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:cratis_chronicle, "~> 3.5"}
  ]
end
```

The client needs Elixir 1.18 or later: the package declares `~> 1.14`, but its `grpc` dependency pulls in `googleapis`, which requires 1.18. CI builds and tests with Elixir 1.19.5 on Erlang/OTP 28.5.

## Prerequisite: Chronicle running

You need a Chronicle kernel before running samples or application code. For local development, pull and run the development image, which bundles MongoDB:

```bash
docker pull cratis/chronicle:latest-development
docker run -d --name chronicle \
  -p 127.0.0.1:35000:35000 \
  -p 127.0.0.1:27017:27017 \
  cratis/chronicle:latest-development
```

The `127.0.0.1:` prefixes keep both ports on your machine: the development kernel accepts well-known credentials and its MongoDB has no authentication. Pull before you run, because the kernel must understand the `cratis_chronicle_contracts` version that `mix deps.get` resolves.

## Getting started

[Get started with the Elixir client](Documentation/get-started.md) walks through installation, connecting, appending an event and reading a read model, including the failure results to expect along the way. The published documentation is at [cratis.io](https://www.cratis.io/chronicle/clients/elixir/), and the API reference is on [HexDocs](https://hexdocs.pm/cratis_chronicle).

## Quick example

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened"

  # Typed defaults: the client derives the event's JSON schema from them.
  defstruct owner: "", balance: 0
end

defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", owner: "", balance: 0

  # owner and balance are mapped by name; id comes from the event source id.
  from MyApp.Events.AccountOpened, set: [id: :event_source_id]
end

defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       # Development-only credentials for the local development kernel.
       connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
       event_store: "my-app",
       otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Then, with the application running (for example in `iex -S mix`):

```elixir
alias Chronicle.Connections.Lifecycle

# The client connects and registers in the background; until then, calls return
# {:error, :not_connected}.
:ok = Lifecycle.wait_until(Lifecycle.name_for(Chronicle.Client), :registered)

:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{owner: "Alice", balance: 1000})

# Projections run asynchronously: this can be {:ok, nil} until the projection catches up.
{:ok, account} = Chronicle.read_model(MyApp.ReadModels.Account, "account-42")
```

## Known limitations in 3.5.0

- Reducers fail to register with the contracts versions the client resolves today (`UndefinedFunctionError` for `...Observation.Reducers.SinkDefinition`), so reducer read models stay empty. Use read models with projections instead.
- Read model projections don't map multi-word event fields such as `owner_name` automatically or from atom expressions; use a camelCase string such as `set: [owner_name: "ownerName"]`.
- Seeders append their events again every time the client registers.
- Tail and next sequence number lookups return `{:ok, 0}` unless you pass `event_source_type: ""` and `event_stream_type: ""`.
- The client skips TLS certificate validation unless the connection string sets `skipTlsValidation=false`.
- `mix deps.get` reports advisories for `grpc 0.11.5`, which is pinned by the generated contracts package.

The [Elixir client documentation](Documentation/index.md) explains each one and its workaround.

## Structure

```text
Source/
  chronicle/       ← cratis_chronicle Hex package
Documentation/     ← Elixir client documentation and client-owned snippets
Samples/
  console/         ← Runnable interactive console sample
```

## Building

```bash
cd Source/chronicle
mix deps.get
mix compile
mix test
```

## Running the console sample

A working example is in the [`Samples/console`](Samples/console) directory. It uses the client from `Source/chronicle` and starts its own kernel with Docker Compose; see its [README](Samples/console/README.md) for controls and details.

```bash
cd Samples/console
docker compose up -d
mix deps.get
mix run --no-halt
```

Set `CHRONICLE_CONNECTION_STRING` to connect to another kernel:

```bash
CHRONICLE_CONNECTION_STRING="chronicle://client-id:client-secret@myserver:35000?skipTlsValidation=false" mix run --no-halt
```

## The Cratis ecosystem

This project is part of [Cratis](https://www.cratis.io) — free, MIT-licensed tools for building event-sourced and CQRS applications.

- **[Chronicle](https://github.com/Cratis/Chronicle)** — event-sourcing database and runtime. Orleans-based kernel, pluggable storage (MongoDB default; PostgreSQL, SQL Server, SQLite, in-memory), language-agnostic gRPC contracts. [Docs](https://www.cratis.io/chronicle/)
- **Chronicle clients** — first-class [.NET SDK](https://github.com/Cratis/Chronicle), plus [TypeScript](https://github.com/Cratis/Chronicle.TypeScript), [Kotlin/Java](https://github.com/Cratis/Chronicle.Kotlin), and this Elixir client; [Python](https://github.com/Cratis/Chronicle.Python) coming soon (pre-alpha). AI agents connect through the [Chronicle MCP server](https://github.com/Cratis/Chronicle.Mcp).
- **[Arc](https://github.com/Cratis/Arc)** — opinionated CQRS framework for ASP.NET Core with commands, queries, validation, authorization, and TypeScript proxy generation. Works without event sourcing. [Docs](https://www.cratis.io/arc/)
- **[Components](https://github.com/Cratis/Components)** — React components aligned with Arc patterns. [Docs](https://www.cratis.io/components/)
- **[CLI](https://github.com/Cratis/cli) + Workbench** — inspect and diagnose Chronicle from the terminal or the browser. [Docs](https://www.cratis.io/cli/)
- **Model-first layer (experimental)** — [Studio](https://github.com/Cratis/Studio), [Screenplay](https://github.com/Cratis/Screenplay), [Stage](https://github.com/Cratis/Stage), [Scene](https://github.com/Cratis/Scene), [Prologue](https://github.com/Cratis/Prologue)
- **Supporting** — [Fundamentals](https://github.com/Cratis/Fundamentals), [Specifications](https://github.com/Cratis/Specifications), [Synopsis](https://github.com/Cratis/Synopsis), [Lens](https://github.com/Cratis/Lens), [Narrator](https://github.com/Cratis/Narrator), and free [AI tooling](https://github.com/Cratis/AI) (preview); [Ensemble](https://github.com/Cratis/Ensemble) coming soon (pre-release)
- **[Samples](https://github.com/Cratis/Samples)** — runnable event sourcing and CQRS samples for the whole stack

Everything Cratis publishes today is MIT licensed and free to use.
