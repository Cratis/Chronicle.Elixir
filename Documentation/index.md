---
title: Chronicle Elixir client
description: The cratis_chronicle Hex package, its requirements and known limitations, and where to find Elixir setup and API details.
---

`cratis_chronicle` is the Elixir client for Chronicle. You declare events, read models, reactors, reducers and seeders as modules with `use` macros, start `Chronicle.Client` in your supervision tree, and append and query with plain functions that return `:ok`, `{:ok, value}` or `{:error, reason}`.

Shared Chronicle concepts and workflows live in the main Chronicle docs and show an Elixir tab where the code differs by client. This section covers what is specific to Elixir: Mix setup, supervision, connections, process-scoped context, and Elixir-only APIs.

**New here?** Start with [Get started](get-started.md). It takes you from `mix new` to a projected read model in a few minutes.

## Requirements and compatibility

| Requirement | Details |
|---|---|
| Package | [`cratis_chronicle`](https://hex.pm/packages/cratis_chronicle) on Hex. These pages describe version 3.5.0. |
| Elixir | 1.18 or later. The package declares `~> 1.14`, but its dependencies need 1.18. CI uses Elixir 1.19.5 on Erlang/OTP 28.5. |
| Kernel | A kernel whose gRPC contracts match the `cratis_chronicle_contracts` version in your `mix.lock`. A mismatch returns `{:error, {:incompatible_server, ...}}`; see [Get started](get-started.md#troubleshooting). |
| API reference | [HexDocs](https://hexdocs.pm/cratis_chronicle) |

## Known limitations in 3.5.0

Check these before you build on the client:

- Reducers don't register with the 19.x contracts packages the client resolves: every attempt logs `Reducer ... failed to register` with an `UndefinedFunctionError` for `Cratis.Chronicle.Contracts.Observation.Reducers.SinkDefinition`, and the reducer's read model stays `{:ok, nil}`. Use read models with projections instead. See [Reducers](reducers.md).
- Automatic mapping and atom expressions in read model projections don't resolve multi-word event fields; map them with camelCase strings. See [Get started](get-started.md#define-a-read-model).
- Seeding appends seed events again every time the client registers. See [Seeding](seeding.md#how-it-runs).
- Tail and next sequence number lookups return `{:ok, 0}` unless you pass empty `:event_source_type` and `:event_stream_type` filters. See [Event sequences](event-sequences.md#sequence-numbers).
- The client doesn't validate the kernel's TLS certificate unless you set `skipTlsValidation=false`, and it has no client-certificate support. See [Connection strings](connections/connection-strings.md#tls).
- `mix deps.get` reports security advisories for the `grpc 0.11.5` dependency, which can't be upgraded until the contracts package allows `grpc 1.x`.

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

- [Get started](get-started.md): install the client, connect to a development kernel, append an event and read a read model
- [Connections](connections/index.md): connection strings, credentials, TLS, and how the client recovers from dropped connections
- [Context management](context.md): process-scoped correlation ids, identities, and causation chains
- [Concepts](concepts.md): strongly typed values and PII classification with `Chronicle.Concept`
- [Seeding](seeding.md): seeders and when seed data is appended
- [Sinks](sinks.md): choosing where read models are stored, and running several clients
- [Event store discovery](event-stores.md): listing event stores and namespaces
- [Event store subscriptions](event-store-subscriptions.md): importing events between event stores
- [Jobs](jobs.md): inspecting and controlling Chronicle jobs
- [Webhooks](webhooks.md): registering webhooks from Elixir
- [External services](external-services.md): registering HTTP and database external services
- [Failed partitions](failed-partitions.md): inspecting observers whose partitions have failed
