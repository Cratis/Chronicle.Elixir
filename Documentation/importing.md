---
title: Importing Events
description: Import large volumes of history into a Chronicle event sequence from any Elixir Enumerable, with chunked, resumable uploads and progress messages.
---

`Chronicle.Imports` brings existing history into an event sequence: a migration from another store, a copy between environments, or fixtures for a load test. The kernel stages and validates every event before committing any, then commits them in order without locking the sequence.

Imports need a Chronicle kernel that serves the import service. An older kernel answers `{:error, :imports_not_supported}`.

## Import from any Enumerable

`Chronicle.Imports.import/2` takes any `Enumerable` of `Chronicle.EventSequences.EventForEventSourceId`, a lazy `Stream` included. The client reads the source while it uploads, so the whole source is never held in memory.

```elixir
{:ok, result} =
  "customers.jsonl"
  |> File.stream!()
  |> Stream.map(&MyApp.Legacy.to_event/1)
  |> Chronicle.Imports.import(progress: self())

result.state             # :completed, :failed or :abandoned
result.events_committed
result.rejections        # [%Chronicle.Imports.ImportRejection{index: 41, event_type: "...", reasons: [...]}]
```

Each entry keeps what its source says about the event: `occurred`, `correlation_id`, `identity` (who caused it), `causation`, `subject`, `tags`, `named_tags`, its event source and stream, and the `generation` of its event type. Set `idempotency_key` (typically the source system's event id) so that running the import again reports the event as already appended, and `source_sequence_number` to keep lineage to the source.

The client cuts the events into chunks within the limits the kernel reports and keeps at most four chunks in flight (`:max_chunks_in_flight`). A chunk whose connection fails is sent again; the kernel stages a chunk once, so a resend never duplicates it.

With the default `on_invalid: :reject`, an import with any invalid event fails and nothing is committed. Use `on_invalid: :skip` to commit the valid events and report the rest.

`import_async/2` runs the same import under a `Task`:

```elixir
task = Chronicle.Imports.import_async(events)
{:ok, result} = Task.await(task, :infinity)
```

## Progress

Pass `progress: pid` to `import/2`, or call `Chronicle.Imports.observe/2` with an import id, and the process receives:

```elixir
{:chronicle_import_progress, import_id, %Chronicle.Imports.ImportProgress{}}
```

until the import completes, fails or is abandoned. A broken progress stream arrives as `{:chronicle_import_progress_error, import_id, reason}`.

## Explicit sessions

For producers that are not one stream, open the session yourself. A session is a value: `add/2` returns the session to use next, once every chunk it sent is acknowledged.

```elixir
{:ok, session} = Chronicle.Imports.begin(event_sequence_id: "event-log")
{:ok, session} = Chronicle.Imports.add(session, first_batch)
{:ok, session} = Chronicle.Imports.add(session, second_batch)
{:ok, result} = Chronicle.Imports.complete(session)
```

`complete/1` waits for the commit unless the session was begun with `wait_for_commit: false`. `abandon/1` discards everything staged.

## Resume after a crash

An import that was not completed stays open on the kernel. Reattach by its id and continue after the events the kernel already holds:

```elixir
{:ok, session} = Chronicle.Imports.reattach(import_id)
remaining = Stream.drop(source, session.events_acknowledged)
{:ok, session} = Chronicle.Imports.add(session, remaining)
{:ok, result} = Chronicle.Imports.complete(session)
```

`import(source, resume: import_id)` does the same in one call. Feed the same events in the same order.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `:client` | `Chronicle.Client` | The client to import through |
| `:namespace` | the client's | The namespace to import into |
| `:event_sequence_id` | `"event-log"` | The event sequence to import into |
| `:on_invalid` | `:reject` | `:reject` commits nothing when any event is invalid; `:skip` commits the rest |
| `:import_id` | generated | The id to give a new import |
| `:wait_for_commit` | `true` | Whether `complete/1` waits for the commit |
| `:max_chunks_in_flight` | `4` | Chunks on the wire at once |
| `:max_events_per_chunk` | the kernel's | A lower chunk size than the kernel allows |
| `:max_chunk_attempts` | `5` | Attempts per chunk after a connection failure |
| `:poll_interval` | `500` | Milliseconds between reads while waiting for the commit |
| `:timeout` | `60_000` | gRPC deadline per call, in milliseconds |

See [Importing events into Chronicle in bulk](https://www.cratis.io/chronicle/events/importing/) for how the kernel stages, validates and commits an import, and how observers see imported events.
