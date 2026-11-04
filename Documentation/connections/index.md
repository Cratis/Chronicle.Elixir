---
title: Connections
description: How the Elixir client holds a long-lived gRPC connection to a Chronicle kernel, and where to configure credentials, TLS and recovery.
---

A Chronicle client keeps one long-lived gRPC connection to a Chronicle kernel. Appending events, registering projections, running reactors and reducers, and seeding all use that connection. Kernels restart, networks fail and load balancers recycle connections; the client handles those interruptions and recovers without losing observers.

Configure the client in your supervision tree, then wait for registration before making your first call. The client owns the connection and its recovery; your application chooses how to handle calls while it is not ready.

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

## Guides

- [Connection strings](connection-strings.md): choose credentials and TLS settings for your kernel, using the `chronicle://` or `chronicle+srv://` format, then keep the connection string in application configuration.
- [Resilience and the connection lifecycle](resilience.md): distinguish an open channel from completed registration, inspect a client that is not ready, and handle calls while the client reconnects. For observers that stop progressing, use the lag and failure diagnostics described there.
- [Keep credentials out of crash reports](crash-reports.md): understand what the client redacts, what can still reach logs, and when to add a filter for other Mint users in your application.
