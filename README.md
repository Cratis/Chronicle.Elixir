# Chronicle Elixir Client

An idiomatic Elixir client for [Cratis Chronicle](https://github.com/Cratis/Chronicle).

## Overview

`cratis_chronicle` provides a clean Elixir API for interacting with the Chronicle Kernel. It builds on the Chronicle gRPC API and exposes OTP-native constructs including:

- **`use Chronicle.EventType`** — annotate structs as event types with stable IDs
- **`use Chronicle.ReadModel`** — declare model-bound projections executed server-side
- **`use Chronicle.Reactor`** — react to events with side effects
- **`use Chronicle.Reducer`** — fold events into read models in your own process
- **`use Chronicle.Seeder`** — seed event stores with baseline events at startup
- **Model-bound constraints** — unique and unique-event-type constraints on event types
- **Context-aware appends** — process-scoped identity, correlation, and causation metadata
- **Optimistic concurrency** — guard appends with scoped tail-sequence checks
- **Transactions** — buffer and commit multi-event units of work
- **Jobs and webhooks** — inspect Chronicle jobs and manage webhook registrations
- **Resilient connection** — automatic reconnection with exponential backoff

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
docker run -p 35000:35000 -p 8080:8080 cratis/chronicle:latest-development
```

## Getting Started

See [Documentation/getting-started.md](./Documentation/getting-started.md) for installation and usage instructions.

## Quick Example

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.EventType, id: "account-opened-v1"
  defstruct [:account_id, :owner_name, :initial_balance]
end

defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModel

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
        connection_string: "chronicle://localhost:35000?disableTls=true",
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
