# Chronicle Elixir Client

`chronicle` is the Elixir SDK for Chronicle. Use this section for Mix setup, supervision, connection behavior, Elixir modules/macros, process-scoped context, and other runtime-specific details.

Shared Chronicle concepts and workflows live in the main Chronicle docs and use language tabs when code differs by client.

## Shared Chronicle topics

- [Get started](/chronicle/get-started/)
- [Events and event logs](/chronicle/events/)
- [Appending events](/chronicle/events/appending/)
- [Read models](/chronicle/read-models/)
- [Projections](/chronicle/projections/)
- [Reactors](/chronicle/reactors/)
- [Reducers](/chronicle/reducers/)
- [Constraints](/chronicle/constraints/)
- [Event seeding](/chronicle/event-seeding/)
- [Compliance](/chronicle/compliance/)
- [Transactions and unit of work](/chronicle/events/transactions/)
- [Event evolution](/chronicle/understanding-event-evolution/)

## Elixir-specific pages

- [Get Started](get-started.md) — install the client, start `Chronicle.Client`, and append an event
- [Connections](connections/index.md) — connection strings, authentication, resilience, and re-registration
- [Context Management](context.md) — process-scoped correlation IDs, identities, and causation chains
- [Event Store Discovery](event-stores.md) — discovering event stores and namespaces
- [Event Store Subscriptions](event-store-subscriptions.md) — importing events between event stores
- [Jobs](jobs.md) — inspecting and controlling Chronicle jobs
- [WebHooks](webhooks.md) — registering webhooks from Elixir
