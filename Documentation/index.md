# Chronicle Elixir Guides

Comprehensive guides for using Chronicle Elixir.

## Guides

- [Model-Bound Constraints](constraints.md) — Declaring unique and unique-event-type constraints directly on event types via `@unique`, `@unique_event_type`, and `@remove_constraint` attributes; automatic registration at client startup
- [Context Management](context.md) — Process-scoped correlation IDs, identity tracking, and causation chains; typical web handler patterns; async process considerations
- [Event Sequences](event-sequences.md) — Organizing events into named sequences (default `"event-log"`); querying and checking sequence state; multi-sequence patterns
- [Event Store Discovery](event-stores.md) — Discovering event stores and namespaces; multi-tenant admin patterns; verifying environment before operations
- [Seeding](seeding/index.md) — Pre-populate your event store with initial events during application startup; define seeders, register them with Chronicle.Client, and use the builder API to organize events by type and source
- [Event Migrations](migrations.md) — Schema evolution between event generations using upcast/downcast transformations; generation validation and event type ID matching
- [Transactions and Unit of Work](transactions.md) — Client-side transaction buffering for atomic multi-event commits; process-scoped UnitOfWorkManager integration
- [Concurrency Scope](concurrency.md) — Optimistic concurrency control by validating sequence tail before append; scoping by event source, stream, or event types
- [Event Store Subscriptions](event-store-subscriptions.md) — Importing events from one Chronicle event store to another; subscription filtering and position control
- [Jobs](jobs.md) — Inspecting and controlling long-running Chronicle operations such as replays, rebuilds, and background work
- [WebHooks](webhooks.md) — Registering webhooks to push observed events to external HTTP endpoints; event type filtering and target configuration
- [Read Models](read-models.md) — Querying Chronicle read models with instance lookup, filtered queries, snapshots, and introspection
