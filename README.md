# Chronicle Elixir Client

Idiomatic Elixir client for the [Chronicle](https://github.com/Cratis/Chronicle) event-sourcing platform.

## Overview

Chronicle is an event-sourcing kernel that stores domain events and projects them into read models. This library provides a clean, idiomatic Elixir interface built on top of the Chronicle gRPC API.

Key features:

- **`use Chronicle.EventType`** — annotate structs as event types with stable IDs
- **`use Chronicle.Reactor`** — react to events with side effects
- **`use Chronicle.Reducer`** — build read models by folding events into state
- **`use Chronicle.ReadModel`** — define read models with model-bound projections
- **Model-bound constraints** — declare unique and unique-event-type constraints on event types
- **Context-aware appends** — process-scoped identity, correlation, and causation metadata
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

This guide uses **projections as the default** because they run inside Chronicle and keep read model updates close to the event store.

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

  alias MyApp.Events.{AccountOpened, FundsDeposited}

  defstruct account_id: nil, owner_name: nil, balance: 0

  from AccountOpened,
    set: [
      account_id: :event_source_id,
      owner_name: :owner_name,
      balance: :initial_balance
    ]

  from FundsDeposited,
    add: [balance: :amount]
end
```

### Constraints (model-bound)

Declare constraints directly on event types:

```elixir
defmodule MyApp.Events.UserRegistered do
  use Chronicle.EventType, id: "user-registered-v1"
  defstruct [:email, :tenant_id]

  @unique [:email, :tenant_id]
  unique_event_type()
end

defmodule MyApp.Events.UserDeleted do
  use Chronicle.EventType, id: "user-deleted-v1"
  defstruct [:email]

  @remove_constraint "email"
end
```

Constraints declared this way are discovered and registered automatically during `Chronicle.Client` startup.

### 3. Define projection mappings (recommended)

Projection mappings are registered on Chronicle and executed server-side.
Each `from/2` maps an event type to:

- A read model key (`$eventSourceId` by default when `:key` is omitted)
- A set of property assignments
- Optional expressions that can use event fields and existing model values

That means Chronicle can maintain read models directly from the event stream without reducer code running in your client process.

The projection mapping is declared directly in the read model module using
`from`, `join`, `removed_with`, and `from_every`.

For expressions, atoms are preferred and more natural:

- `:owner_name`, `:amount` for event fields
- `:event_source_id`, `:occurred` for built-in context values
- string expressions only for advanced cases

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

If your Chronicle artifacts are defined in one OTP app, use `otp_app` and let
Chronicle discover event types, reactors, reducers, and read models automatically.

```elixir
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

You can also inspect event-store metadata and event-sequence state:

```elixir
{:ok, stores} = Chronicle.get_event_stores()
{:ok, namespaces} = Chronicle.get_namespaces()

{:ok, has_events?} = Chronicle.has_events_for?("account-42")
{:ok, tail_sequence_number} = Chronicle.get_tail_sequence_number("account-42")
```

### Correlation, identity, and causation

You can set process-scoped correlation, identity, and causation context.
`Chronicle.append/3` automatically includes this metadata on append requests.

```elixir
alias Chronicle.{CausationManager, CorrelationId, Identity}

Chronicle.set_correlation_id(CorrelationId.create())
Chronicle.set_identity(Identity.new("user-42", "Alice", "alice"))

CausationManager.define_root(%{application: "banking-api"})
CausationManager.add("Banking.Commands.OpenAccount", %{account_id: "account-42"})

:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})

Chronicle.clear_identity()
Chronicle.clear_correlation_id()
CausationManager.clear()
```

For one-off overrides, pass explicit metadata as options:

```elixir
:ok =
  Chronicle.append("account-42", event,
    correlation_id: "92a130f7-16e2-44f7-a8e3-79e76f5df3e1",
    identity: Chronicle.Identity.new("service-1", "Billing Service", "billing")
  )
```

To append/query a non-default event sequence, pass `:event_sequence_id`:

```elixir
:ok = Chronicle.append("account-42", event, event_sequence_id: "audit-sequence")
{:ok, events} = Chronicle.EventLog.get_for_event_source("account-42", event_sequence_id: "audit-sequence")
```

## Quick Start (Reducer Alternative)

Use reducers when you want the read model folding logic in Elixir code in your app process.
In this mode, Chronicle streams events to the reducer and your reducer returns the next model state.

### 1. Define a reducer

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

### 2. Start Chronicle.Client with reducers

With auto-discovery:

```elixir
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

Projections are the recommended default. They are model-bound mappings declared
on `Chronicle.ReadModel` and executed server-side by Chronicle:

```elixir
defmodule MyApp.ReadModels.Account do
  use Chronicle.ReadModel

  alias MyApp.Events.{AccountOpened, FundsDeposited}

  defstruct account_id: nil, owner_name: nil, balance: 0

  from AccountOpened,
    set: [
      account_id: :event_source_id,
      owner_name: :owner_name,
      balance: :initial_balance
    ]

  from FundsDeposited,
    add: [balance: :amount]
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

## Comprehensive Guides

For detailed information on specific features, see the [guides](Documentation/index.md):

- **[Model-Bound Constraints](Documentation/constraints.md)** — Declaring unique and unique-event-type constraints on event types
- **[Context Management](Documentation/context.md)** — Correlation IDs, identity tracking, and causation chains
- **[Event Sequences](Documentation/event-sequences.md)** — Organizing events into separate logical streams
- **[Event Store Discovery](Documentation/event-stores.md)** — Discovering event stores and namespaces

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
        artifacts.ex      # Artifact auto-discovery helpers
        event_type.ex     # use Chronicle.EventType macro with constraints
        seeder.ex         # use Chronicle.Seeder behaviour
        seeding.ex        # Event seeding builder API
        reactor.ex        # use Chronicle.Reactor behaviour
        reducer.ex        # use Chronicle.Reducer behaviour
        read_model.ex     # use Chronicle.ReadModel macro
        event_log.ex      # Append and query events with context
        event_types.ex    # Register event types with Chronicle
        constraints.ex    # Constraint discovery and registration
        event_stores.ex   # Event store and namespace discovery
        read_models.ex    # Query read model instances
        correlation_id.ex # Correlation ID values
        correlation_id_manager.ex  # Process-scoped correlation
        identity.ex       # Identity values
        identity_provider.ex       # Process-scoped identity
        causation_entry.ex         # Causation chain entries
        causation_manager.ex       # Process-scoped causation building
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
