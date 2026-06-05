# Connections

A Chronicle client maintains a long-lived gRPC connection to a Chronicle
kernel. Everything the client does — appending events, projecting read models,
running reactors and reducers, seeding — flows over that one connection. Because
it is long-lived, it *will* be interrupted: kernels restart, networks blip, load
balancers recycle. The client is built to treat those interruptions as normal
and recover from them without losing observers or dropping into a broken state.

These guides explain how the connection is established, how it is described, and
how the client stays resilient when it drops.

## Guides

- [Resilience and the Connection Lifecycle](resilience.md) — How the client
  connects, detects a dead connection, reconnects, and re-registers every
  observer in the correct order.
- [Connection Strings](connection-strings.md) — The `chronicle://` URL format,
  authentication modes, and the available options.

## At a glance

Start a client by pointing it at a kernel with a connection string:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000?disableTls=true",
  event_store: "store",
  otp_app: :my_app}
```

The client connects in the background. Calls such as `Chronicle.append/3` work as
soon as the connection is ready; you never manage the socket yourself.
