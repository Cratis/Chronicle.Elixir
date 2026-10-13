---
sharedTopicBridge: true
---

# Reactors

Reactors are documented in the shared Chronicle docs with synchronized examples for C#, Kotlin, Java, Elixir, and TypeScript.

- [Getting started with reactors](/chronicle/reactors/getting-started/)
- [Reactor event processing](/chronicle/reactors/event-processing/)
- [Reactors overview](/chronicle/reactors/)

Use the [Elixir get started page](/chronicle/clients/elixir/get-started/) for client startup and supervision setup.

## Side-effect appending

`handle/2` can return `{:ok, event_or_events}` in addition to `:ok`/`{:error, reason}`, and
Chronicle.Elixir appends the returned event(s) as a side effect right after `handle/2`
returns. Mirrors C#'s `Reactors/SideEffects` and Kotlin's `ReactorsService.appendSideEffects`.

Returning a single event struct appends it to the same event source that triggered the
handler:

```elixir
defmodule MyApp.Reactors.OrderNotifier do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{OrderPlaced, OrderConfirmationQueued}

  @handles OrderPlaced

  @impl true
  def handle(%OrderPlaced{} = event, _context) do
    {:ok, %OrderConfirmationQueued{customer_id: event.customer_id}}
  end
end
```

Return a list of events to append them all atomically to that same event source. To target
a **different** event source, wrap the event in a
`Chronicle.EventSequences.EventForEventSourceId`; a list of these (optionally mixed with
bare event structs, which are normalized to the triggering event source) is appended
atomically across all their event source ids in one call.

If appending the side effect fails, `handle/2`'s overall result becomes
`{:error, reason}` — reported the same way as a plain `{:error, reason}` return.

## Replay lifecycle hooks

Implement any of `on_replay_begin/0`, `on_replay_end/0`, `on_partition_replay_begin/1`, or
`on_partition_replay_end/1` to be notified when Chronicle starts or finishes replaying this
reactor — either as a whole, or for a single partition (event source). All four are
optional. Mirrors C#'s `ICanBeNotifiedWhenReplay` / `ICanBeNotifiedWhenPartitionReplayed`.

```elixir
defmodule MyApp.Reactors.ReplayAwareNotifier do
  use Chronicle.Reactors.Reactor

  require Logger

  alias MyApp.Events.OrderPlaced

  @handles OrderPlaced

  @impl true
  def handle(%OrderPlaced{}, _context), do: :ok

  @impl true
  def on_replay_begin, do: Logger.info("Replay starting")

  @impl true
  def on_replay_end, do: Logger.info("Replay finished")
end
```

These are notifications, not events to handle — they run outside normal `handle/2`
dispatch, are not subject to failed-partition tracking, and a raised exception is logged
and swallowed rather than reported to Chronicle.

## Replay: once-only and replay handlers

Reactors are replayable by default: when the kernel replays an observer, `handle/2` runs again for
past events. That is wrong for side effects such as sending an email. Mirrors .NET's `[OnceOnly]`
and `[Replay]`.

```elixir
# Never replayed: registered with the kernel as not replayable.
use Chronicle.Reactors.Reactor, once_only: true

# Replayable, but these events are skipped while replaying.
use Chronicle.Reactors.Reactor, once_only: [MyApp.Events.OrderShipped]
```

While a replay is running `context.replaying?` is `true`. Define the optional `handle_replay/2`
to handle replayed events differently - when present it is called *instead of* `handle/2`:

```elixir
@impl true
def handle(%OrderPlaced{} = event, _context), do: send_confirmation(event)

@impl true
def handle_replay(%OrderPlaced{} = event, _context), do: update_projection_cache(event)
```

Excluding replays is not exactly-once delivery: recovering a failed partition can deliver an event
again as an ordinary observation. Guard side effects with the delivery id below.

## Delivery identity

Every reactor invocation context carries `delivery_id`: a stable identity of *this delivery of this
event to this reactor*, the same value each time the event is redelivered. It is derived like the
.NET `ReactorDelivery.Id`: the reactor id, event store, namespace, event sequence id, event source
id and sequence number joined with `#`. Use it as the key of whatever records that the side effect
happened:

```elixir
def handle(%OrderPlaced{} = event, %{delivery_id: delivery_id}) do
  case Receipts.insert_once(delivery_id) do
    :inserted -> Mailer.send_confirmation(event)
    :already_there -> :ok
  end
end
```

The id identifies the delivery; it does not make the external effect atomic with the receipt.

## Middleware

`Chronicle.Middleware` wraps the handling of an event in a reactor or reducer, for tracing,
metrics, logging or impersonating the identity that caused the event:

```elixir
defmodule MyApp.Middleware.Timing do
  @behaviour Chronicle.Middleware

  @impl true
  def call(event, context, next) do
    {micros, result} = :timer.tc(fn -> next.(event, context) end)
    Logger.info("handled in #{micros}us")
    result
  end
end

config :cratis_chronicle, middleware: [MyApp.Middleware.Timing]            # every reactor and reducer
use Chronicle.Reactors.Reactor, middleware: [MyApp.Middleware.Impersonate]  # one module
```

Global middleware is the outer layer, then the module's own, each in the order listed.
