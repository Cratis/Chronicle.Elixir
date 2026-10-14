---
title: Captures
description: Define Chronicle captures with the Elixir DSL, register them, and manage their lifecycle.
---

`Chronicle.Captures.Capture` provides a DSL for defining Chronicle captures, and `Chronicle.Captures` provides an idiomatic Elixir API for registering, starting, stopping, deleting, listing, and validating them.

Captures turn data that arrives from outside the event log — an external API, an inbound webhook, or another event store's public events — into events appended to this event store. The DSL compiles at build time to Capture Declaration Language (CDL) text, the same text the kernel's Workbench and `SaveCapture` accept. See the Chronicle documentation's Capture Declaration Language reference for the full grammar.

:::caution[The capturing engine runs a subset of the language]
As of Chronicle 19.6, the kernel's capturing engine reads only `api` and `events` sources, and runs only root-level `append` rules — `map`, `nested`, and `children` compile and validate, but are not applied at runtime.
:::

## Defining a capture

```elixir
defmodule MyApp.Captures.InvoiceCapture do
  use Chronicle.Captures.Capture, name: "InvoiceCapture"

  api_source("InvoicingApi", route: "/invoices", poll: "10m")

  key("id")

  append MyApp.Events.InvoiceStatusChanged, when: "status" do
    set(:status, "$.status")
  end
end
```

- `use Chronicle.Captures.Capture` registers `:name` (defaults to the module's last segment) and `:id` (defaults to a deterministic UUIDv5 derived from the module's full name, so re-registering the same module updates the same kernel-side capture rather than creating a new one every deploy). Pass `start: true` to have `Chronicle.Captures.Registrar` start the capture once it has been saved.
- Exactly one source is required: `api_source/1,2` (polls a named [External Service](external-services.md)), `webhook_source/1` (an inbound webhook path), or `events_source/1` (captures from another event store's public events, given as a list of registered `Chronicle.Events.EventType` modules).
- `key/1` names the property path used to identify and diff a captured item. For an events source, use `"$eventSourceId"`.
- `append/2,3` declares an event to append when its `when:` condition matches; `set/2` inside its block maps a target field of the event's struct from a source expression (`"$.path"` for the current payload, `"$context.<property>"` for the capture or event context).

:::caution[An append's event type must start with an uppercase letter]
The kernel's CDL parser lexes the target of `append <EventType>` as a type-name token that must start with an uppercase letter and contain only letters, digits, and underscores — no hyphens — even though Chronicle otherwise lets you register an event type with any id. Register the event type you intend to append from a capture with a matching id:

```elixir
# Works as an append target - starts with an uppercase letter.
use Chronicle.Events.EventType, id: "InvoiceStatusChanged"

# Compiles, but can never be targeted by append/2,3 (fails at compile time with a clear error).
use Chronicle.Events.EventType, id: "invoice-status-changed"
```

`append/2,3` raises `ArgumentError` at compile time when the resolved id does not match this shape, rather than letting the capture fail validation on the kernel. `events_source/1`'s `from` lines have no such restriction — the kernel's grammar treats them as free text.
:::

## `when:` conditions

```elixir
append MyApp.Events.CustomerChanged, when: "firstName" do
  set(:first_name, "$.firstName")
end

append MyApp.Events.CustomerChanged, when: {:any, ["firstName", "lastName"]} do
  set(:first_name, "$.firstName")
end

append MyApp.Events.CustomerActivated, when: {:transition, "status", "inactive", "active"} do
  set(:status, "$.status")
end

append MyApp.Events.ItemAdded, when: :added do
  set(:line_number, "$.lineNumber")
end
```

- a string — fires when that property changes
- `{:any, [...]}` / `{:all, [...]}` — an "or"/"and" of several properties
- `{:transition, property, from, to}` — fires when a property moves between two specific values
- `:added` / `:removed` — fires when the item is first seen or disappears
- `{:expression, "template"}` — a raw CDL expression

## Map operations

```elixir
map do
  rename(:full_name, :fornavn)
  template(:greeting, "Hello, ${fornavn}")
  translate(:status, :status, [{"aktiv", "active"}, {"inaktiv", "inactive"}])
  split(:full_name, by: ",", into: [:first_name, :last_name])
end
```

## Nested and children scopes

```elixir
nested :billing_address do
  map do
    rename(:street, :"fakturaAdresse.gate")
  end

  append MyApp.Events.BillingAddressChanged, when: "street" do
    set(:street, "$.street")
  end
end

children :line_items, identified_by: :line_number do
  append MyApp.Events.ItemAdded, when: :added do
    set(:line_number, "$.lineNumber")
  end
end
```

## Registering a capture

Register a capture module explicitly with `Chronicle.Client`:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  captures: [MyApp.Captures.InvoiceCapture]}
```

Or rely on `otp_app:` auto-discovery — modules that export `__chronicle_capture__/1` are discovered automatically, the same way reactors, reducers, and webhooks are. Either way, `Chronicle.Captures.Registrar` saves every discoverable capture once the client's connection reaches the `:registered` phase, and re-registers on every reconnect:

- It is idempotent: it compares the compiled declaration against what `Chronicle.Captures.list/1` reports and skips a capture whose declaration already matches.
- It warns, rather than fails, before saving over a capture that is `:started` and whose declaration changed — saving a started capture stops it on the kernel, so it comes back stopped.
- It starts a capture only when it declares `start: true`.

## Managing a capture directly

```elixir
{:ok, capture} = Chronicle.Captures.register(MyApp.Captures.InvoiceCapture)
:ok = Chronicle.Captures.start(MyApp.Captures.InvoiceCapture)
{:ok, captures} = Chronicle.Captures.list()
{:ok, messages} = Chronicle.Captures.validate(MyApp.Captures.InvoiceCapture)
{:ok, events} = Chronicle.Captures.captured_events("InvoiceCapture")
:ok = Chronicle.Captures.stop(MyApp.Captures.InvoiceCapture)
:ok = Chronicle.Captures.delete(MyApp.Captures.InvoiceCapture)
```

Every function also accepts a raw capture id (a GUID string) instead of a module for `start/2`, `stop/2`, and `delete/2`, and raw CDL text instead of a module for `validate/2` — useful for validating a declaration before it is ever saved.

## Introspection

```elixir
MyApp.Captures.InvoiceCapture.__chronicle_capture__(:id)
MyApp.Captures.InvoiceCapture.__chronicle_capture__(:name)
MyApp.Captures.InvoiceCapture.__chronicle_capture__(:declaration)
MyApp.Captures.InvoiceCapture.__chronicle_capture__(:start?)
```
