---
title: Connections
description: How the Elixir client holds a long-lived gRPC connection to a Chronicle kernel, and where to configure credentials, TLS and recovery.
---

A Chronicle client keeps one long-lived gRPC connection to a Chronicle kernel. Everything the client does flows over it: appending events, registering projections, running reactors and reducers, seeding. Because it is long-lived, it *will* be interrupted: kernels restart, networks blip, load balancers recycle connections. The client treats those interruptions as normal and recovers from them without losing observers.

## Guides

- [Connection strings](connection-strings.md): the `chronicle://` and `chronicle+srv://` formats, client credentials and API keys, TLS validation, and the other options.
- [Resilience and the connection lifecycle](resilience.md): how the client connects, registers your artifacts, detects a dead session and reconnects, and what your calls return while it does.

## At a glance

Start a client in your supervision tree with a connection string:

```elixir
{Chronicle.Client,
 connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
 event_store: "my-app",
 otp_app: :my_app}
```

That connection string carries the development kernel's well-known credentials. Use real credentials, and `skipTlsValidation=false`, for any other kernel.

The client connects in the background. Until it has a channel, appends and most other calls return `{:error, :not_connected}` rather than waiting, and registration of your artifacts finishes a little later. Wait for readiness before your first call:

```elixir
alias Chronicle.Connections.Lifecycle

:ok = Lifecycle.wait_until(Lifecycle.name_for(Chronicle.Client), :registered)
```

You never manage the socket, the session, or re-registration yourself.
