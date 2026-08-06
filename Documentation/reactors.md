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
