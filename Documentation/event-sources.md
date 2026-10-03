---
title: Event sources and streams
description: Declare named event sources and streams, register them at startup, and append through them from Elixir.
---

# Event sources and streams

An event source definition gives appends a stable name, optional named streams and default concurrency dimensions. The definition belongs to the append, not to the event type: the same event type can be appended through different event sources.

Definitions are optional. Appends that don't name an event source behave exactly as before and carry no registered-source metadata. Registered definitions need Chronicle 19.30.0 or newer.

## Declare a definition

```elixir
defmodule MyApp.AccountEventSource do
  use Chronicle.EventSources.EventSource,
    name: "Account",
    description: "A bank account",
    concurrency: [:event_source_id]

  stream "Transactions",
    description: "Money movements",
    concurrency: [:event_source_id, :event_stream_id]
end
```

`:name` defaults to the module's last segment without a trailing `EventSource`. Concurrency dimensions are any of `:event_source_id`, `:event_source_type`, `:event_stream_type` and `:event_stream_id`. A stream that declares none inherits the dimensions of its source. A module that declares the same stream name twice fails to compile.

## Register

`Chronicle.Client` discovers event source modules together with event types and registers them on every (re)connect, right after event types and before any observer starts. You can also pass them explicitly:

```elixir
{Chronicle.Client,
 connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
 event_sources: [MyApp.AccountEventSource]}
```

Two modules that use the same source name raise `Chronicle.EventSources.DuplicateEventSourceName` when the client starts. Registration is an upsert; definitions you leave out of a later registration stay registered in the kernel.

## Append through a definition

```elixir
Chronicle.EventSequences.EventLog.append("account-1", %MyApp.Events.FundsDeposited{amount: 50},
  event_source: MyApp.AccountEventSource,
  event_stream: "Transactions",
  event_stream_id: "2024-05"
)
```

The source name becomes the event source type and the `EventSource` metadata of the event, and the stream name becomes the event stream type. `append_many/3` and units of work take the same options. Without `:event_stream` the stream type is `"All"`.

A source can be given by module or by name. A mismatch is rejected before anything is sent:

| Error | Cause |
| --- | --- |
| `{:unknown_event_source, source}` | The source isn't registered with the client. |
| `{:event_stream_does_not_belong_to_event_source, source, stream}` | The source doesn't declare the stream. |
| `{:event_routing_contradicts_event_source, source, dimension, expected, actual}` | An explicit `:event_source_type` or `:event_stream_type` disagrees with the definition. |
| `{:event_stream_without_event_source, stream}` | `:event_stream` was given without `:event_source`. |

### Mixed sources in one transaction

Each `Chronicle.EventSequences.EventForEventSourceId` entry can carry its own `event_source` and `event_stream`. They win over the `:event_source` and `:event_stream` options of `append_many_for_event_sources/2`, which apply only to entries that name none. If one entry doesn't resolve, nothing is appended.

## Concurrency

When you append through a definition without a `:concurrency_scope`, the client reads the tail sequence number narrowed by the dimensions that apply (the stream's, or the source's if the stream declares none) and sends it as the scope. An explicit `:concurrency_scope`, including `ConcurrencyScope.none()`, always wins and no read is made. With no dimensions declared, no scope is sent.

## Event context

Reactor and reducer contexts have an `:event_source` key holding the name of the event source the event was appended through, or `nil` for events appended without one.
