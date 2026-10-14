---
title: Limits and gaps
description: Kernel limits to size your data against, the consistency guarantees of appends and projections, and what the Elixir client does not do yet.
---

## Kernel limits

| Limit | Value | What happens |
|---|---|---|
| Message size | 4 MiB per gRPC message | The client refuses larger payloads with `{:error, {:payload_too_large, size, limit}}`; a reducer whose read model exceeds it reports the reduction as failed. Configure with `config :cratis_chronicle, max_payload_bytes: ...`. |
| Read model document | 4 MiB | Roughly 18,000 entries at 220-250 bytes each. A child collection that can grow without bound belongs in its own read model per child, not one document. |
| Observer subscriber deadline | `observers.subscriberTimeout`, 5 seconds by default | Applies to a reactor or reducer handling one batch. Keep handlers fast, and size partitions so a backlog delivered in one call finishes within it. |
| Filtered read model queries | `:max_scan`, 10,000 instances | See [Filtering and sorting](read-models.md#filtering-and-sorting): the filter is applied by the client. |

## Consistency

- `Chronicle.append/3` returning `:ok` means the event is stored. Projections, reducers and reactors process it **afterwards and asynchronously**.
- A read model read right after an append, including `append_many/3`, may not reflect it yet. When you need your own write, use `Chronicle.EventSequences.EventLog.append_and_wait_for_completion/3` or `AppendResult.wait_for_completion/2`, which return once the affected observers have processed the event (or failed).
- `await_registration/2` returns once the client's artifacts are registered. Observers subscribe right after; wait for the first events you depend on with the calls above rather than sleeping.
- `get/3` returns `{:ok, nil}` both for a key that does not exist and for one that is not projected yet.

## Security

`skipTlsValidation` defaults to `true` so that a development kernel works without setup. A connection to a remote host that skips validation logs a warning at startup. Production connection strings must say `skipTlsValidation=false`; see [Connection strings](connections/connection-strings.md#tls).

## Not supported yet

- The filter of `query/2` is evaluated by the client, not the kernel.
- `Chronicle.Testing.InMemoryKernel` models appends, reads, concurrency scopes and `unique`/`unique_event_type` constraints, but not `closes_stream` constraints or the read model and projection query surface. Use `Chronicle.Testing.Integration` against a running kernel for those, and note that the kernel has no way to delete the event stores those specs create.
- A shared read model subscription that reconnects does not replay the changes made while it was down, because the kernel's watch request cannot resume from a sequence number. Query again after `{:chronicle_read_model_watch_resumed, model}`.
- `Chronicle.Projections.preview/2` runs a registered projection's declaration over a stored event sequence; previewing a projection over events you supply is not possible.
- Webhook sources in captures cannot carry authentication, and the kernel engine currently runs only `api` and `events` sources.
- Event metadata carries no content hash or size; the hash of an event is on its `EventContext`.
- Projections have no `min`/`max` operations, because the kernel has no such expressions.
- Constraint drift is not detected, because the kernel cannot list registered constraints.
- Trace context is not stored on events by the kernel, so observer spans are not linked to the append that caused them.

See the repository's open issues for the current list.
