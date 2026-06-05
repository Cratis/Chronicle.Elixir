# Event Types

Events are the facts of your system — immutable records of things that happened.
Every event in Chronicle has a stable type identifier and a generation number,
so the kernel can register its schema, route it to observers, and migrate it as
it evolves.

## Defining an event type

Define a struct and annotate it with `Chronicle.Events.EventType`, giving it a
stable `id`:

```elixir
defmodule MyApp.Events.AccountOpened do
  use Chronicle.Events.EventType, id: "account-opened-v1"
  defstruct [:account_id, :owner_name, :initial_balance]
end
```

The `id` is the contract between your client and the kernel — keep it stable.
The struct fields are the event's payload; they are serialized to JSON when the
event is appended and decoded back into the struct when observed.

## Naming and shape

- Name events in the **past tense**: `AccountOpened`, `FundsDeposited`,
  `AddressChanged`. An event describes something that already happened.
- Give each event **one purpose**. If you find yourself adding a field that is
  only sometimes set, that is a second event, not an optional field.

## Generations

When an event's shape changes, bump its generation and provide a migration
rather than mutating the original. A higher generation marks a new version of
the same logical event:

```elixir
defmodule MyApp.Events.FundsDeposited do
  use Chronicle.Events.EventType, id: "funds-deposited", generation: 2
  defstruct [:account_id, :amount, :currency]
end
```

See [Event Migrations](migrations.md) for how generations are upcast and
downcast.

## Constraints

You can declare uniqueness rules directly on an event type, and Chronicle
enforces them at append time. See
[Model-Bound Constraints](constraints.md) for the full set of attributes.

## Registration

Event types are discovered automatically when you start the client with
`otp_app:`, or you can list them explicitly via `event_types:`. The client
registers them with the kernel as part of the ordered connect sequence, before
any observer attaches.
