---
sharedTopicBridge: true
---

# Concurrency

Optimistic concurrency is shared Chronicle behavior. Use the shared docs for concurrency scopes, expected sequence numbers, and client-tabbed examples.

- [Optimistic concurrency](/chronicle/events/concurrency/)
- [Appending events](/chronicle/events/appending/)
- [Elixir client setup](./get-started.md)

## Elixir-specific additions

These are new to the Elixir client and not covered by the shared docs above; see
[Event Sequences](./event-sequences.md#concurrency) for the builder helpers, `at_tail/2`,
the client's default `:concurrency` strategy option, and the duplicate-scope batch error.
