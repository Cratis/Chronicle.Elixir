---
title: Connection strings
description: The chronicle:// and chronicle+srv:// URL formats, authentication modes, TLS options, and Chronicle.Client overrides for the Elixir client.
---

A connection string tells the client which kernel to connect to, how to authenticate and how to secure the channel. It is a URL, so host, port, credentials and options travel in one value you can keep in an environment variable.

```text
chronicle://[client-id:client-secret@]host[:port][,host[:port]...][?option=value&...]
chronicle+srv://service-name[?option=value&...]
```

Pass it to `Chronicle.Client` as `connection_string:`, either as a string or as a `Chronicle.Connections.ConnectionString` struct. When you pass none, the client uses `chronicle://localhost:35000`, which has no credentials.

## Authentication

The client supports two authentication modes, chosen by what the connection string contains.

**Client credentials** go in the URL userinfo. The client exchanges them for an OAuth access token at the kernel's `/connect/token` endpoint, attaches the token to every call, and refreshes it before it expires:

```text
chronicle://client-id:client-secret@chronicle.example.com:35000
```

**An API key** goes in the `apiKey` query parameter and is sent as an `api-key` header on every call. When a connection string has both, the API key wins:

```text
chronicle://chronicle.example.com:35000?apiKey=your-api-key
```

With neither, the client connects without authentication. grpc 1.x retains channel and per-call headers in its response-process state, so moving authentication into a per-call interceptor alone does not keep secrets out of an OTP crash report. The client installs a primary Logger filter that replaces Mint response-process termination reports with a redacted notice before handlers receive them. This covers those dependency crash reports, not application logging, custom gRPC connections, or other processes that inspect or print credentials. Keep connection strings and request metadata out of logs, and restrict access to production logs.

The Elixir client does **not** substitute Chronicle's development credentials the way the .NET client does. A development kernel that requires authentication accepts the connection but never lets the client finish registering, so spell the development credentials out locally:

```text
chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000
```

`Chronicle.Connections.ConnectionString.development/0` returns the same value as a struct. These credentials are well known and only meaningful to a kernel configured to accept them; never configure a shared or production kernel with them.

URL-encode reserved characters in a client id or secret, such as `@`, `:` and `/`. The client decodes both as form-encoded values, so a literal `+` must be written as `%2B`, or it becomes a space.

## Options

| Option | Default | Purpose |
|--------|---------|---------|
| `apiKey` | none | API key sent with every call. Takes precedence over client credentials. |
| `skipTlsValidation` | `true` | Whether to skip validating the server's certificate chain. Set `false` to validate against the operating system's trust store. Applies to the gRPC channel and the token request. |
| `disableTls` | `false` | Connect over plain HTTP/2. The kernel requires TLS on its port, so only use this behind a proxy that terminates TLS for you. |
| `loadBalancer` | `least-connections` | How to pick among several hosts or SRV-resolved addresses: `least-connections`, `round-robin` or `random`. |
| `srvNameServer` | system resolver | For `chronicle+srv://`, the DNS server to query, as `host` or `host:port`. |
| `authPort` | the first host's port | Port for the `/connect/token` request, when it differs from the gRPC port. |
| `certificatePath` | none | Path to a PKCS#12 (`.p12`/`.pfx`) file or a PEM bundle containing a client certificate and private key. Applied to the gRPC channel and OAuth token request. An empty value is treated as absent. |
| `certificatePassword` | none | Password for a PKCS#12 file or encrypted PEM private key. An empty value without `certificatePath` is ignored; a non-empty value without a path, or with an empty path, is rejected at startup (unlike the .NET client). |

A host without a port uses `35000`. IPv6 addresses use brackets, as in `chronicle://[::1]:35000`.

## TLS

The Chronicle kernel always serves TLS. In development it generates a self-signed certificate on every start, which no client can validate. So by default the Elixir client encrypts the connection but **accepts any server certificate without validating it**. That lets you connect to a development kernel with no setup, but on its own it doesn't protect against a server impersonating your kernel.

:::danger[Turn on certificate validation outside development]
Give production kernels a certificate your operating system trusts, and add `skipTlsValidation=false` to the connection string:

```text
chronicle://client-id:client-secret@chronicle.example.com:35000?skipTlsValidation=false
```

The Elixir client does not use the configured client certificate to trust the server, unlike the .NET client's fallback. To connect to a kernel with a self-signed certificate while validating the server, provide its certificate as a trusted CA through the gRPC credential's `:cacerts` option. `skipTlsValidation=true` is for development only.
:::

If your kernel requires mutual TLS, set `certificatePath` to a PKCS#12 (`.p12`/`.pfx`) file or a PEM file containing both the client certificate and private key. Include intermediate certificates in the bundle when the server trusts only the root. Supply `certificatePassword` when the file is password-protected. PKCS#12 loading requires the `openssl` executable. If OpenSSL 3 rejects an older PKCS#12 encryption algorithm, the client retries with OpenSSL's legacy provider (`-legacy`), which must be available. The password is passed through standard input, never a command-line argument, and the extracted key stays in memory. The client presents the certificate to both the gRPC channel and the OAuth token endpoint; the private key stays in a process-owned signing table rather than the channel credential. An unreadable file, invalid certificate, or wrong password fails connection startup; `disableTls=true` cannot be combined with a client certificate. A configured client certificate must use the Mint gRPC adapter. The certificate is matched to its private key, regardless of bundle order; mismatched bundles fail at startup. Conflicting custom TLS identity options and Mint module-level `transport_opts` are rejected at startup because grpc 1.0.5 still merges module options after the credential and would otherwise replace the client identity.

With a client certificate, put server-verification options on the `GRPC.Credential` passed as `:cred` through `:grpc_options`, not in `:adapter_opts` `:transport_opts`; adapter-level server-verification options are rejected at startup. Server verification uses Mint/OTP defaults or the caller's credential settings, not the client certificate. OTP 28 supports Ed25519 client identities with TLS 1.3 only; for TLS 1.2, use an RSA or ECDSA identity.

A client certificate does not validate the *server*. To trust a private certificate authority, install it in the operating system's trust store and set `skipTlsValidation=false`, or supply its certificate in `:cacerts` on a gRPC credential with `verify: :verify_peer`. For example, pass `grpc_options: [cred: GRPC.Credential.new(ssl: [verify: :verify_peer, cacerts: [trusted_der]])]`, where `trusted_der` is the DER-encoded trusted certificate. A gRPC credential controls server trust only for the gRPC channel: the client-credentials token request always follows `skipTlsValidation` and the system trust store. When `certificatePath` is configured, the client certificate is added to the gRPC credential even if you pass your own `:cred`.

The client requires grpc 1.x, Mint 1.11 or later, and Elixir 1.18 or later. It explicitly selects the Mint adapter; grpc 1.x makes Gun optional and no longer requires you to supervise `GRPC.Client.Supervisor`. If your application calls `GRPC.Stub.connect/2` independently, select `adapter: GRPC.Client.Adapters.Mint` there too (or add Gun as a direct dependency).

## Several hosts and DNS SRV

List several hosts, comma-separated, and the client picks one on every connect and reconnect using the `loadBalancer` strategy:

```text
chronicle://client-id:client-secret@chronicle-1:35000,chronicle-2:35000,chronicle-3:35000
```

`chronicle+srv://` resolves a single name through a DNS SRV lookup of `_chronicle._tcp.<name>` instead. The lookup runs again on every connection attempt, so membership changes are picked up without a restart:

```text
chronicle+srv://chronicle.example.com
```

Client-credential tokens are always requested from the first configured host. Least-connections HTTP probes do not present a client certificate; if your kernel requires mutual TLS on `/connections/count` or `/connections/reserve`, use `loadBalancer=round-robin` or `loadBalancer=random` for multiple hosts.

## Chronicle.Client overrides

Some settings can also be passed straight to `Chronicle.Client`, where they win over the connection string:

| Client option | Overrides |
|---------------|-----------|
| `:skip_tls_validation` | `skipTlsValidation` |
| `:load_balancer` | `loadBalancer` (`:least_connections`, `:round_robin` or `:random`) |
| `:grpc_options` | Extra options for `GRPC.Stub.connect/2`, such as `:cred` |
| `:reconnect_base_delay`, `:reconnect_max_delay` | The reconnect backoff, in milliseconds. See [Resilience](resilience.md). |

## Examples

Keep the connection string in configuration rather than in code, for example in `config/runtime.exs`:

```elixir
import Config

config :my_app, :chronicle_connection_string, System.fetch_env!("CHRONICLE_CONNECTION_STRING")
```

Then read it when you start the client:

```elixir
{Chronicle.Client,
 connection_string: Application.fetch_env!(:my_app, :chronicle_connection_string),
 event_store: "my-app",
 otp_app: :my_app}
```

Typical values:

```text
# Local development kernel
chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000

# Production with client credentials and certificate validation
chronicle://my-service:client-secret@chronicle.example.com:35000?skipTlsValidation=false

# Production with an API key and certificate validation
chronicle://chronicle.example.com:35000?apiKey=your-api-key&skipTlsValidation=false
```

`Chronicle.Connections.ConnectionString.parse/1` raises `ArgumentError` for a malformed string, so a bad value fails when the client starts rather than on the first call. Don't log a connection string as-is, because it can contain a secret.
