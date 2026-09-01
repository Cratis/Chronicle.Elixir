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
    {:cratis_chronicle, "~> 2.2"}
  ]
end
```

## Structure

```text
Source/
  chronicle/       ← cratis_chronicle Hex package
Documentation/     ← User-facing documentation
Samples/
  console/         ← Runnable console example
```

## Prerequisite: Chronicle Running

You need a Chronicle Kernel available before running samples or application code.

The easiest local setup is the development Docker image:

```bash
docker run -p 35000:35000 cratis/chronicle:latest-development
```

## Getting Started

See [Documentation/get-started.md](./Documentation/get-started.md) for installation and usage instructions.

## Quick Example

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened-v1"
  defstruct [:account_id, :owner_name, :initial_balance]
end

defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.AccountOpened

  defstruct account_id: nil, owner_name: nil, balance: 0

  from AccountOpened,
    set: [
      account_id: :event_source_id,
      owner_name: :owner_name,
      balance: :initial_balance
    ]
end

defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        event_store: "my-app",
        otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# Append an event
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{
  account_id: "account-42",
  owner_name: "Alice",
  initial_balance: 1000
})

# Read back the current read model
{:ok, account} = Chronicle.read_model(MyApp.ReadModels.Account, "account-42")
```

## Building

```bash
cd Source/chronicle
mix deps.get
mix compile
```

## Running the Console Sample

A working example is in the [`Samples/console`](Samples/console) directory.

**Prerequisites:** A Chronicle kernel running locally on port 35000.

```bash
cd Samples/console
mix deps.get
mix run --no-halt
```

Set `CHRONICLE_CONNECTION_STRING` to override the default connection:

```bash
CHRONICLE_CONNECTION_STRING="chronicle://myserver:35000?apiKey=secret" mix run --no-halt
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
