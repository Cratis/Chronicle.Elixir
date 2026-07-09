# Get Started

This guide takes you from an empty project to a running Chronicle client that
appends and reads events.

## Install

Add the client to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:cratis_chronicle, "~> 0.1"}
  ]
end
```

Then fetch it:

```shell
mix deps.get
```

You also need a running Chronicle kernel. For local development, the kernel
listens on `localhost:35000` over TLS, serving an auto-generated self-signed
certificate — the client trusts it out of the box, no configuration needed.

## Define an event

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened-v1"
  defstruct [:account_id, :owner_name, :initial_balance]
end
```

See [Event Types](events.md) for the full guide.

## Start the client

Add `Chronicle.Client` to your application's supervision tree. With `otp_app:`,
it discovers your event types, reactors, reducers, read models and seeders
automatically:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        event_store: "my-store",
        otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

The client connects in the background and recovers automatically if the
connection drops. See
[Resilience and the Connection Lifecycle](connections/resilience.md).

## Append an event

```elixir
:ok =
  Chronicle.append("account-1", %MyApp.Events.AccountOpened{
    account_id: "account-1",
    owner_name: "Alice",
    initial_balance: 500
  })
```

## Read it back

```elixir
{:ok, events} =
  Chronicle.EventSequences.EventLog.get_for_event_source("account-1")
```

## Where to next

- [Reducers](reducers.md) and [Reactors](reactors.md) to build read models and
  side effects from your events.
- [Read Models](read-models.md) and [Projections](projections.md) to query and
  shape projected state.
- [Constraints](constraints.md) for uniqueness and append-time invariants.
- [Event Sequences](event-sequences.md) and [Concurrency](concurrency.md) for
  the event log and optimistic concurrency.
- [Transactions](transactions.md) for unit-of-work semantics across appends.
- [Migrations](migrations.md) for evolving event schemas over time.
- [Compliance](compliance.md) for PII handling and GDPR erasure.
- [Connections](connections/index.md) to understand connection strings and
  resilience.
