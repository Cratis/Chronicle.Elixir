# Chronicle Elixir Client

Idiomatic Elixir client for the [Chronicle](https://github.com/Cratis/Chronicle) event-sourcing platform.

## Overview

Chronicle is an event-sourcing kernel that stores domain events and projects them into read models. This library provides a clean, idiomatic Elixir interface built on top of the Chronicle gRPC API.

Key features:

- **`use Chronicle.EventType`** — annotate structs as event types with stable IDs
- **`use Chronicle.Reactor`** — react to events with side effects
- **`use Chronicle.Reducer`** — build read models by folding events into state
- **`use Chronicle.Projection`** — declare server-side read model projections
- **Resilient connection** — automatic reconnection with exponential backoff
- **OTP-native** — fits naturally in your supervision tree

## Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:cratis_chronicle, "~> 0.1"}
  ]
end
```

## Quick Start

### 1. Define event types

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.EventType, id: "account-opened-v1"
  defstruct [:account_id, :owner_name, :initial_balance]
end

defmodule MyApp.Events.FundsDeposited do
  use Chronicle.EventType, id: "funds-deposited-v1"
  defstruct [:account_id, :amount]
end
```

### 2. Define a read model

```elixir
defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModel
  defstruct account_id: nil, owner_name: nil, balance: 0
end
```

### 3. Define a reducer

Reducers fold events into a read model, one event at a time:

```elixir
defmodule MyApp.Reducers.AccountReducer do
  use Chronicle.Reducer, model: MyApp.ReadModels.Account

  @handles MyApp.Events.AccountOpened
  @handles MyApp.Events.FundsDeposited

  @impl true
  def reduce(%MyApp.Events.AccountOpened{} = event, _model, _context) do
    %MyApp.ReadModels.Account{
      account_id: event.account_id,
      owner_name: event.owner_name,
      balance: event.initial_balance
    }
  end

  def reduce(%MyApp.Events.FundsDeposited{} = event, model, _context) do
    %{model | balance: model.balance + event.amount}
  end
end
```

### 4. Define a reactor (optional)

Reactors react to events with side effects:

```elixir
defmodule MyApp.Reactors.NotificationReactor do
  use Chronicle.Reactor

  @handles MyApp.Events.AccountOpened

  @impl true
  def handle(%MyApp.Events.AccountOpened{} = event, _context) do
    MyApp.Mailer.send_welcome(event.owner_name)
    :ok
  end
end
```

### 5. Start Chronicle.Client in your supervision tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000?disableTls=true",
        event_store: "my-app",
        event_types: [
          MyApp.Events.AccountOpened,
          MyApp.Events.FundsDeposited
        ],
        reactors: [MyApp.Reactors.NotificationReactor],
        reducers: [MyApp.Reducers.AccountReducer]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 6. Append events and query read models

```elixir
# Append a single event
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{
  account_id: "account-42",
  owner_name: "Alice",
  initial_balance: 1000
})

# Append multiple events atomically
:ok = Chronicle.append_many("account-42", [
  %MyApp.Events.FundsDeposited{account_id: "account-42", amount: 500},
  %MyApp.Events.FundsDeposited{account_id: "account-42", amount: 200}
])

# Read back the current read model
{:ok, account} = Chronicle.read_model(MyApp.ReadModels.Account, "account-42")
IO.inspect(account)
# => %MyApp.ReadModels.Account{account_id: "account-42", owner_name: "Alice", balance: 1700}

# Get all instances
{:ok, accounts} = Chronicle.all(MyApp.ReadModels.Account)
```

## Connection Strings

Chronicle connection strings use the `chronicle://` scheme:

| Format | Use |
|--------|-----|
| `chronicle://localhost:35000` | No authentication (development) |
| `chronicle://localhost:35000?disableTls=true` | Disable TLS for local dev |
| `chronicle://client-id:secret@server:35000` | Client credentials |
| `chronicle://server:35000?apiKey=my-key` | API key authentication |
| `chronicle+srv://service-name:35000` | SRV record lookup |

```elixir
alias Chronicle.Connections.ConnectionString

# Parse a string
cs = ConnectionString.parse("chronicle://localhost:35000?disableTls=true")

# Use helpers
cs = ConnectionString.default()      # chronicle://localhost:35000
cs = ConnectionString.development()  # includes dev credentials

# Modify
cs = ConnectionString.with_api_key(cs, "my-api-key")
cs = ConnectionString.with_credentials(cs, "client-id", "secret")
```

## Declarative Projections

As an alternative to reducers, projections declare server-side property mappings. Chronicle executes them on the kernel, enabling richer query capabilities:

```elixir
defmodule MyApp.Projections.AccountProjection do
  use Chronicle.Projection, model: MyApp.ReadModels.Account

  @impl true
  def define do
    import Chronicle.Projection.Builder

    new()
    |> from(MyApp.Events.AccountOpened,
        key: "$eventSourceId",
        properties: %{
          "account_id" => "$eventSourceId",
          "owner_name" => "OwnerName",
          "balance" => "InitialBalance"
        })
    |> from(MyApp.Events.FundsDeposited,
        key: "$eventSourceId",
        properties: %{"balance" => "$add(Amount, balance)"})
  end
end
```

## Multiple clients

Run multiple Chronicle.Client instances for different event stores:

```elixir
{Chronicle.Client,
  name: :bank,
  connection_string: "chronicle://bank-server:35000",
  event_store: "bank",
  event_types: [...]}

{Chronicle.Client,
  name: :crm,
  connection_string: "chronicle://crm-server:35000",
  event_store: "crm",
  event_types: [...]}

# Specify which client to use
Chronicle.append("customer-1", event, client: :crm)
Chronicle.read_model(Account, "account-1", client: :bank)
```

## Running the Console Sample

A working example is in the [`Samples/console`](Samples/console) directory.

**Prerequisites:** A Chronicle kernel running locally on port 35000.

```shell
cd Samples/console
mix deps.get
mix run --no-halt
```

Set `CHRONICLE_CONNECTION_STRING` to override the default connection:

```shell
CHRONICLE_CONNECTION_STRING="chronicle://myserver:35000?apiKey=secret" mix run --no-halt
```

## Local Development

### Prerequisites

- Elixir 1.14+ and OTP 25+
- A running Chronicle kernel (see [Chronicle](https://github.com/Cratis/Chronicle))

### Setup

```shell
cd Source/chronicle
mix deps.get
mix compile
mix test
```

### Running tests

The unit tests do not require a running Chronicle instance:

```shell
mix test
```

### Code formatting

```shell
mix format
```

### Generating documentation

```shell
mix docs
open doc/index.html
```

## Package structure

```
Source/
  chronicle/              # The cratis/chronicle Hex package
    lib/
      chronicle.ex        # Convenience API
      chronicle/
        connections/
          connection_string.ex
          connection.ex
        client.ex         # Supervisor entry point
        event_type.ex     # use Chronicle.EventType macro
        reactor.ex        # use Chronicle.Reactor behaviour
        reducer.ex        # use Chronicle.Reducer behaviour
        projection.ex     # use Chronicle.Projection behaviour
        projection/
          builder.ex      # Fluent projection builder
        read_model.ex     # use Chronicle.ReadModel macro
        event_log.ex      # Append and query events
        event_types.ex    # Register event types with Chronicle
        constraints.ex    # Register event constraints
        read_models.ex    # Query read model instances
        reactors/
          handler.ex      # gRPC streaming reactor handler
        reducers/
          handler.ex      # gRPC streaming reducer handler
        projections/
          registrar.ex    # Projection registration GenServer

Samples/
  console/                # Runnable console example
```

## License

MIT — see [LICENSE](LICENSE).
