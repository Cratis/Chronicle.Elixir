# Connection Strings

A connection string tells the client which kernel to connect to and how to
authenticate. It is a URL with the `chronicle://` scheme, so it carries the host,
port, credentials and options in one value you can keep in config or an
environment variable.

```
chronicle://host:port?option=value&option=value
```

The default, when you pass no connection string, is
`chronicle://localhost:35000` — the local development kernel.

## Authentication

Two modes are supported.

**Client credentials** — supply a client id and secret in the URL userinfo:

```
chronicle://client-id:client-secret@host:35000
```

**API key** — supply an `apiKey` query parameter:

```
chronicle://host:35000?apiKey=my-api-key
```

When neither is present the client connects without authentication, which is the
normal case for local development.

## Options

| Option | Purpose |
|--------|---------|
| `apiKey` | API key used for authentication. |
| `disableTls` | Set to `true` to connect over plain HTTP/2 instead of TLS. The Chronicle kernel requires TLS on its single port, so only set this when connecting through something else that terminates TLS for you, such as a plaintext-terminating proxy. |
| `certificatePath` | Path to a client certificate file for mutual TLS. |
| `certificatePassword` | Password for the client certificate. |

## Examples

Local development:

```elixir
{Chronicle.Client, connection_string: "chronicle://localhost:35000"}
```

TLS is mandatory even for local development — the kernel auto-generates a
self-signed certificate for `localhost` when none is configured, and the
client trusts it automatically, no setup required.

Production with an API key over TLS:

```elixir
{Chronicle.Client, connection_string: "chronicle://chronicle.internal:35000?apiKey=#{api_key}"}
```

Client credentials:

```elixir
{Chronicle.Client, connection_string: "chronicle://my-client:#{secret}@chronicle.internal:35000"}
```

## Why a URL

Putting everything in one URL keeps connection configuration in a single place —
one environment variable per environment — rather than spreading host, port,
credentials and flags across several settings that can drift out of sync.
