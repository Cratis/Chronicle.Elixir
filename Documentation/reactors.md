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

## Starting at the tail

A new reactor catches up from the very beginning of the event sequence, as ordinary observation,
so a reactor whose handlers cause side effects acts on every historical event the moment it is
deployed. `once_only` does not prevent that, because it only excludes replay. Set
`start_at_tail: true` and the first time Chronicle sees the reactor it begins at the tail of the
event sequence and observes only what is appended afterwards:

```elixir
use Chronicle.Reactors.Reactor, start_at_tail: true
```

The option only affects the first registration: a reactor that already has a position keeps it, so
it never skips events after a restart. Changing the module name without pinning `:id` makes a new
reactor, which starts at the tail again. An explicit replay still replays from the beginning. Both
the Chronicle server and this client must support it; a server that predates it ignores the request
and the reactor catches up from the beginning.

## Pinned generation delivery

By default (`:compatibility`), Chronicle upgrades every event to the handled module's own
generation before delivery, so `handle/2` always sees that generation's shape regardless of which
generation was actually appended. That is the right default when the handler is written against
the current generation.

Set `generation_delivery: :pinned` when the handler is written against an **older** generation and
must see events exactly as that generation was appended, instead of upgraded to the current one:

```elixir
use Chronicle.Reactors.Reactor, generation_delivery: :pinned
```

`context.appended_generation` then tells you which generation was actually appended (`0` means
unknown — an older kernel, or an event appended outside a registered event source).

A client-wide default applies to every reactor that doesn't set its own `:generation_delivery`:

```elixir
{Chronicle.Client,
  ...
  event_generation_delivery: :pinned}
```

A reactor's own option always wins over the client default. With `:pinned`, a reactor handling two
generations of the same event type id has no single generation to pin to and raises
`Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver` on start.

## Pinning the id

`use Chronicle.Reactors.Reactor` defaults the reactor's id to its full module name. Renaming
or moving the module then changes that id, and Chronicle treats it as a *different* reactor —
its observation position resets, replaying events the previous name had already handled.
Pin the id explicitly so the module can be renamed or moved freely:

```elixir
use Chronicle.Reactors.Reactor, id: "order-notifier"
```

A reactor relying on the module-name default gets a one-time warning (per module, for the life
of the BEAM node) from [discovery](./discovery.md), naming the module and showing this fix. Pass
`warn_defaulted_ids: false` to `Chronicle.Client` to suppress it. See
[Discovery and artifact identity drift](./discovery.md).

## Handling events in batches

Chronicle delivers events in **pages**: a page holds the events of one or more event sources, in
sequence order, on every path (live, catch-up, replay and retry). The client always asks for
pages. `handle/2` keeps working unchanged: it is called once per event, event source by event
source.

A **batch function** is called once per page instead, with every event of the types it observes.
Declare it with one `@observes` attribute per event type, just before the function, and
pattern-match on the `{event, context}` pairs of the `Chronicle.Observers.EventBatch` it
receives:

```elixir
defmodule MyApp.Reactors.Users do
  use Chronicle.Reactors.Reactor

  alias Chronicle.Observers.EventBatch

  @observes MyApp.Events.UserRegistered
  @observes MyApp.Events.UserRenamed
  @observes MyApp.Events.UserRemoved
  def index(batch, _context) do
    operations =
      Enum.map(batch, fn
        {%MyApp.Events.UserRegistered{name: name}, ctx} -> {:upsert, ctx.event_source_id, name}
        {%MyApp.Events.UserRenamed{new_name: name}, ctx} -> {:upsert, ctx.event_source_id, name}
        {%MyApp.Events.UserRemoved{}, ctx} -> {:delete, ctx.event_source_id}
      end)

    response = MyApp.Search.bulk(operations)

    batch = Enum.reduce(response.failed, batch, &EventBatch.fail(&2, &1, :index_failed))
    Enum.reduce(response.throttled, batch, &EventBatch.defer(&2, &1, 5_000))
  end

  # A per-event handler in the same reactor, for a type no batch function observes.
  @handles MyApp.Events.UserEmailChanged

  @impl true
  def handle(%MyApp.Events.UserEmailChanged{} = event, _context), do: MyApp.Mailer.confirm(event)
end
```

The second argument is a `Chronicle.Observers.BatchContext`: the observer, event store,
namespace, the partitions and event count of the page, its first and last sequence numbers, the
deadline, and `origin` - `:live`, `:catch_up`, `:replay` or `:retry`.

Each event type reaches exactly one function. The reactor refuses to start when an event type is
observed by two batch functions, or observed by a batch function and also declared with
`@handles`, when `@observes` precedes `handle/2` or `handle_replay/2`, or when a batch function
does not take `(batch, context)`. Each refusal raises an exception from `Chronicle.Observers`.

Order is kept per function: each function sees its events in sequence order, and so in order
within each event source. Two functions of one reactor are not ordered relative to each other, so
side effects that must happen in a particular order belong in the same function.

A batch function returns:

- `:ok` - every event source in the batch succeeded.
- the batch, after `EventBatch.fail/3` or `EventBatch.defer/3` - only those event sources fail or
  are delivered again after the delay, from their first event in the batch or from the event a
  context points at. A deferral is not a failure and does not count towards quarantine.
- `{:error, reason}`, or it raises - every event source in the batch fails at its first event in
  the batch.

Returning events is not supported in a batch function: append through `Chronicle.EventSequences.EventLog`.
When the functions of a reactor report different outcomes for one event source, it settles at the
earliest event reported, and everything from there is delivered again, so keep side effects
idempotent and use the [delivery identity](#delivery-identity) to recognize a redelivery.

A Chronicle server before 19.122 sends one event source at a time. Batch functions still work,
but cannot defer: a deferral fails the event source with
`Chronicle.Observers.DeferralNotSupportedByKernel`, and failed-partition recovery delivers it
again.

Bound the pages with the `:batch_size` option:

```elixir
use Chronicle.Reactors.Reactor,
  batch_size: [max_events: 1_000, max_bytes: 4_194_304, max_delay_milliseconds: 50]
```

Unset bounds are left to the Chronicle server. A page that spans several event sources runs on
its own, after the batches before it and before the ones after it. [Middleware](#middleware)
wraps `handle/2` only; it does not wrap batch functions.

## Concurrency

A reactor handles batches for different event sources at the same time, up to 16 by default. Batches for one event source always run one at a time, in the order Chronicle sends them. A slow event source therefore no longer holds up all the others, and the reactor keeps up with a large catch-up or replay.

Because of this, `handle/2` can run in several processes at once. Keep shared state in something built for concurrent access, such as a database, an ETS table or a `GenServer`, and not in the process dictionary or module attributes. Tune the limit with the `:max_concurrent_partitions` client option. Set it to `1` to handle every batch one after another, as versions before 3.16 did. Reducers follow the same rules, per read model instance.

Each batch Chronicle sends also says how long Chronicle waits for its result. If a batch only gets its turn after that time, Chronicle has already given up on it and will send the events again, so the client answers it as failed right away instead of handling it. The `[:chronicle, :observer, :batch, :expired]` telemetry event reports when that happens. A Chronicle server before 19.114 sends no deadline, and every batch is handled.

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
