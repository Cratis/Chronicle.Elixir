# Resilience and the Connection Lifecycle

A Chronicle client is a small supervision tree of processes that all depend on
one thing: a live connection to the kernel. Reactors, reducers, projections,
seeders, webhooks and subscriptions all need that connection, and they all need
it to come *back* after it drops. Rather than have each of them poll and retry
on its own — which races, reconnects in the wrong order, and registers observers
before the kernel knows about them — the client funnels every part through a
single connection lifecycle.

This mirrors the behavior of the .NET Chronicle client, so the two clients
recover identically.

## The three phases

The lifecycle moves through three ordered phases:

| Phase | Meaning |
|-------|---------|
| `:disconnected` | No live session with the kernel. |
| `:connected` | The session handshake completed — the kernel has acknowledged the client's connection id. The channel can carry calls. |
| `:registered` | The base artifacts (event store, namespace, event types, read models, constraints, projections) are registered with the kernel. Observers may now safely attach. |

Splitting `:connected` from `:registered` is the important part. A reducer's
observation stream cannot be registered until the kernel already knows about the
reducer's read model. If observers attached the moment the connection came up,
they would race ahead of those definitions and the kernel would reject them.
Waiting for `:registered` removes that race entirely.

## What happens on connect

When the connection is established, the client always runs the same ordered
registration, on first connect and on every reconnect:

1. Ensure the event store and namespace exist.
2. Register event types and read models.
3. Register constraints and projections (including reducer read-model
   definitions).
4. Advance to `:registered`.
5. Reactors and reducers open their observation streams; webhook and
   subscription registrars register; seeders run.

Steps 1–3 must complete before step 5 — that ordering is what keeps observers
from registering against definitions that do not exist yet.

## What happens on disconnect

The client keeps a keepalive stream open to the kernel. When keepalives stop
arriving, the connection is considered dead:

1. The lifecycle moves to `:disconnected`.
2. Reactors and reducers tear down their observation streams and wait.
3. The connection id is rotated, so the next session uses a fresh identity —
   exactly as the .NET client does.
4. The client reconnects with exponential backoff, and the connect sequence
   above runs again from the top.

Because reactors register as replayable and projections and reducers are
rewindable, any events that arrive while an observer is briefly detached are
picked up by replay once it re-attaches — nothing is missed.

## Seeding is connection-aware

Seeders no longer run on a fixed delay at startup. They run when the lifecycle
reaches `:registered`, so they never fail with `:not_connected`. Seeding is
idempotent — it skips event sources that already have events — so re-running it
after a reconnect is a cheap no-op.

## Failure isolation

Each observer manages its own stream-level retry: if a single reactor or reducer
stream fails while the connection is otherwise healthy, only that stream
re-registers, after a short delay. A failing observer never takes down the
connection or its siblings.

## You don't manage any of this

All of the above is automatic. You start a `Chronicle.Client`, and appends,
queries, reactors and reducers keep working across kernel restarts and network
interruptions without any reconnect code of your own.
