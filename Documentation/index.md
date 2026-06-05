# Chronicle Elixir Guides

Comprehensive guides for using Chronicle Elixir.

## Guides

- [Model-Bound Constraints](constraints.md) — Declaring unique and unique-event-type constraints directly on event types via `@unique`, `@unique_event_type`, and `@remove_constraint` attributes; automatic registration at client startup
- [Context Management](context.md) — Process-scoped correlation IDs, identity tracking, and causation chains; typical web handler patterns; async process considerations
- [Event Sequences](event-sequences.md) — Organizing events into named sequences (default `"event-log"`); querying and checking sequence state; multi-sequence patterns
- [Event Store Discovery](event-stores.md) — Discovering event stores and namespaces; multi-tenant admin patterns; verifying environment before operations
