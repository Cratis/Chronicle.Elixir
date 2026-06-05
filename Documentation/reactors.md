# Reactors

A reactor is the "when this happens, do that" of event sourcing. It observes
events as they are appended and produces side effects: sending an email, calling
an external API, or triggering a command in another part of the system. Unlike a
reducer, a reactor does not build state — it reacts.

## Defining a reactor

Use `Chronicle.Reactors.Reactor`, declare the event types it handles with
`@handles`, and implement a `handle/2` clause per event:

```elixir
defmodule MyApp.Reactors.WelcomeMailer do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{AccountOpened, AccountClosed}

  @handles AccountOpened
  @handles AccountClosed

  @impl true
  def handle(%AccountOpened{} = event, context) do
    MyApp.Mailer.send_welcome(event.owner_email)
    :ok
  end

  def handle(%AccountClosed{} = event, _context) do
    MyApp.Mailer.send_goodbye(event.owner_email)
    :ok
  end
end
```

`handle/2` receives the decoded event struct and a context map with metadata:

| Key | Description |
|-----|-------------|
| `:event_source_id` | The event source (aggregate) the event belongs to. |
| `:sequence_number` | The event's position in the sequence. |
| `:occurred` | When the event occurred. |
| `:event_store` / `:namespace` | Where the event lives. |

Return `:ok` on success. If `handle/2` raises, the failing partition pauses
until the issue is resolved, so the event is never silently skipped.

## Registering a reactor

Reactors are discovered automatically when you start the client with
`otp_app:`, or you can list them explicitly:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000?disableTls=true",
  event_store: "store",
  reactors: [MyApp.Reactors.WelcomeMailer]}
```

The client registers the reactor with the kernel once the connection reaches the
`:registered` phase, and re-registers it automatically on every reconnect. See
[Resilience and the Connection Lifecycle](connections/resilience.md).

## Design for idempotency

A reactor may observe the same event more than once — during replay, recovery,
or after a reconnect. Make side effects safe to repeat: check whether the work
was already done, use idempotency keys, or design the downstream call to
tolerate duplicates.

## Triggering further events

A reactor should never write to the event log directly. When a reaction needs to
produce new events, execute a command (or append through the normal client API)
so the write goes through the same path as any other — keeping the event log the
single source of truth.
