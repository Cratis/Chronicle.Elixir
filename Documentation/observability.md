---
title: Observability
description: OpenTelemetry spans, telemetry events, and trace propagation in the Elixir client, following the shared Cratis OpenTelemetry convention.
---

The Elixir client instruments the operations it performs against a Chronicle kernel with [OpenTelemetry](https://opentelemetry.io) spans and `:telemetry` events, following the shared Cratis OpenTelemetry convention ([`Cratis/Architecture#33`](https://github.com/Cratis/Architecture/issues/33)). The convention keeps span, attribute, and metric names the same across every Chronicle client language, so a collector groups them together regardless of which language produced a given span.

## Always on, export is your choice

Instrumentation runs whether or not an OpenTelemetry SDK is installed — there is no Chronicle-specific "enable tracing" switch. The client depends only on `opentelemetry_api`; with no SDK (the `opentelemetry` and `opentelemetry_exporter` applications) started in your release, every span and propagation call is a documented no-op and nothing leaves the process.

To actually collect and export traces, add the SDK and exporter to your own application, and configure them the standard OpenTelemetry way — through `OTEL_*` environment variables or application configuration. The client adds no configuration surface of its own for this.

```elixir
# mix.exs
{:opentelemetry, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.6"}
```

```elixir
# config/runtime.exs
config :opentelemetry,
  resource: [service: [name: "my-app"]],
  text_map_propagators: [:trace_context]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4318"
```

## Instrumentation scope

Every span uses the `Cratis.Chronicle.Client` instrumentation scope — the same string the .NET, TypeScript, and Kotlin clients use, so `AddSource("Cratis.*")`-style collector configuration catches every Chronicle client regardless of language.

## Spans

| Span name | Kind | Where |
| --- | --- | --- |
| `cratis.chronicle.client.event_sequence.append` | Client | `Chronicle.EventSequences.EventLog.append/3`, `append_with_result/3` |
| `cratis.chronicle.client.event_sequence.append_many` | Client | `append_many/3`, `append_many_with_result/3`, `append_many_for_event_sources/2`, and a `Chronicle.Transactions.UnitOfWork.commit/1` |
| `cratis.chronicle.client.reactor.handle` | Consumer | a reactor's `handle/2` (and `handle_replay/2`) delivery |
| `cratis.chronicle.client.reducer.reduce` | Consumer | a reducer's `reduce/3` delivery |

A span's status is set to error when the wrapped operation returns `{:error, _}` (this client's ordinary tagged-tuple failure shape), and an exception raised inside it is recorded on the span before re-raising — tracing never swallows a failure.

## Attributes

| Attribute | Notes |
| --- | --- |
| `cratis.event_store.name` | |
| `cratis.event_store.namespace` | |
| `cratis.event_sequence.id` | |
| `cratis.event_type.id` | Append spans only — the event being appended |
| `cratis.event.count` | `append_many` and unit-of-work commit spans |
| `cratis.observer.id` | Reactor/reducer spans — the reactor or reducer's id |
| `cratis.correlation_id` | |
| `cratis.event_source.id` | **Off by default** — see below |

### `cratis.event_source.id` is opt-in

An event source id can itself be sensitive, so it is never set on a span unless explicitly enabled:

```elixir
config :cratis_chronicle, trace_event_source_id: true
```

## `:telemetry` events

For applications that build metrics on `:telemetry` rather than an OpenTelemetry metrics exporter, the same operations also emit `:telemetry` spans — `:start`, `:stop`, and `:exception` events, per [`:telemetry.span/3`](https://hexdocs.pm/telemetry/telemetry.html#span-3):

- `[:cratis, :chronicle, :client, :append, :start | :stop | :exception]`
- `[:cratis, :chronicle, :client, :reactor, :handle, :start | :stop | :exception]`
- `[:cratis, :chronicle, :client, :reducer, :reduce, :start | :stop | :exception]`

```elixir
:telemetry.attach(
  "append-duration",
  [:cratis, :chronicle, :client, :append, :stop],
  fn _event, %{duration: duration}, metadata, _config ->
    Logger.info("Appended #{metadata.event_count} event(s) in #{System.convert_time_unit(duration, :native, :millisecond)}ms")
  end,
  nil
)
```

The `:stop` event's metadata carries `error: true` when the operation returned `{:error, _}`, alongside the event count and sequence id. This is separate from the observer-lag telemetry described in [Observers](observers.md#lag) (`[:chronicle, :observer, :lag]`), which predates this convention and is not renamed by it.

## Trace propagation

Every outbound gRPC call carries the W3C `traceparent`/`tracestate` headers for whichever OpenTelemetry span is active in the calling process, injected by `Chronicle.Connections.TracePropagationInterceptor`. This interceptor is always installed — like the rest of this instrumentation, it does nothing without an SDK-configured propagator, and is not something you configure or disable per connection.

This means a trace that started in your application (an HTTP request, a Phoenix LiveView event) continues into the Chronicle kernel when your handler for it calls `Chronicle.EventSequences.EventLog.append/3` or a query, as long as the call happens inside the active span — for example inside `OpenTelemetry.Tracer.with_span/2`.

## Not covered

- Stored kernel trace context: the kernel does not yet persist the append's trace context with the event, so an observer's delivery span is not yet linked back to the append that caused it (tracked upstream in Chronicle kernel issues).
- OpenTelemetry metrics: only `:telemetry` events are emitted today; an OTel metrics instrument for the same measures is a future addition.
