---
title: Keep credentials out of crash reports
description: When gRPC and Mint crash reports can print your API key or bearer token, and the production Logger setup that keeps them out of shipped logs.
---

The client authenticates every call with an API key or an OAuth bearer token, sent as request headers. The gRPC and Mint libraries underneath it keep those headers in process state. When one of those processes crashes, OTP writes its state, last message and stacktrace arguments to the log at `:error` level, so an unprotected crash report can contain your credentials in clear text. Chronicle's own processes hide their credentials from crash reports, and the client installs a primary Logger filter that does the same for the dependency processes. You don't need an application-level filter for the report shapes below.

## What the client redacts

`Connection.connect/2` installs a primary Logger filter (`Chronicle.Connections.ResponseCrashRedaction`). A primary filter runs before any handler formats the event, including Elixir's own OTP report translator, so it covers the console, files and every handler you add. The filter replaces only the parts that carry credentials and keeps the rest of the report readable:

| Report | What is replaced | What stays |
| --- | --- | --- |
| `gen_server`, `gen_statem` and `gen_event` terminate reports | The state, last message and reason where they hold a gRPC stream, `GRPC.Client.Connection`, the Mint connection process state, a Mint HTTP/2 connection or an HPACK table, or an `api-key` or `authorization` header | The process, the callback and function, the reason and the stacktrace |
| `proc_lib` crash reports (with `handle_sasl_reports: true`) | The same parts, including message queue contents | Initial call, ancestors, links, status |
| Supervisor `child_terminated`, `start_error` and shutdown reports (with `handle_sasl_reports: true`) | The same parts in the reason and in the child's start arguments | The supervisor, the child id, restart type |
| The Mint response process termination report | The whole report, replaced by a one-line notice such as `gRPC Mint response process terminated (RuntimeError); crash report suppressed to protect authentication headers` | The notice names the failure class |
| Plain string and format log events at `:warning` or above | The API key, the password and the OAuth tokens this client has used, wherever they occur, and the value of any `api-key`, `authorization` or `Bearer` text | Everything else in the message |

A redacted part is printed as a placeholder such as `:"[redacted: GRPC.Client.Adapters.Mint.ConnectionProcess.State holds request headers]"` or as `[redacted]`.

Why the filter has to look at several shapes: the `StreamResponseProcess` state holds the whole `%GRPC.Client.Stream{}`, including the channel's `api-key` header and the per-call `authorization` header. Mint's HTTP/2 connection keeps the headers it has sent in its HPACK encode table, and `api-key` is not in the static table, so the value is stored there; that is in the `ConnectionProcess` state. `GRPC.Client.Connection` holds the channel and its headers. The client also sends `enable_push: false` to Mint, which removes the route where a server `PUSH_PROMISE` frame crashes `ConnectionProcess`.

The client remembers the credential values it uses only in memory, in a list of at most 16 values (the newest win, so a rotating token cannot grow it), so it can scrub them from free-form text. They are never logged or written anywhere else. Values shorter than eight characters are ignored, because scrubbing them would mangle unrelated log text.

## What can still reach a log

The filter is a client-side safeguard, not a guarantee:

- It is installed at runtime by the first `Connection.connect/2`. Anything logged before that is not covered, and it does not survive a restart of the `:logger` application.
- It recognizes the known state shapes and credential header names. A crash report that holds a credential in some other form, for example a secret you pass in your own process state or message, is not recognized. Text scrubbing only knows the values this client has used.
- It does not look at `:info` and `:debug` text events, or at messages your own code builds.
- Process state can still be read outside logging: `:sys.get_state/1`, the observer, remote shells and crash dumps.

If you need more than that, keep `handle_sasl_reports` at its default `false`, restrict who can read production logs, and rotate an API key or client secret that has appeared in one.

## The root fix is upstream

Redacting in the client works around the library, and it works for the shapes known today. The complete fix is in `grpc`: implementing `format_status/1` on `StreamResponseProcess`, `ConnectionProcess` and `GRPC.Client.Connection` so request headers are redacted from crash reports, and not crashing on a malformed `grpc-status`. That change belongs to elixir-grpc. When a release contains it, the client's filter becomes a second layer rather than the only one.

## Optional: also protect other Mint users

The client's filter is credential-aware. It does not hide the crashes of other processes in your application that use Mint, such as an HTTP client with its own secrets. If you want one filter for all of them, install your own primary filter that replaces matching reports with a notice, and keep it separate from the client's:

```elixir
defmodule MyApp.MintCrashReportFilter do
  @moduledoc false

  @notice "Report of a Mint process crash suppressed: it can contain credentials"

  def filter(%{msg: {:report, report}} = event, _extra) do
    if mentions_mint?(report), do: %{event | msg: {:string, @notice}}, else: :ignore
  end

  def filter(_event, _extra), do: :ignore

  defp mentions_mint?(atom) when is_atom(atom),
    do: atom |> Atom.to_string() |> String.starts_with?("Elixir.Mint.")

  defp mentions_mint?(%{} = map), do: map |> Map.to_list() |> mentions_mint?()
  defp mentions_mint?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> mentions_mint?()
  defp mentions_mint?([head | tail]), do: mentions_mint?(head) or mentions_mint?(tail)
  defp mentions_mint?(_other), do: false
end
```

```elixir
:ok =
  :logger.add_primary_filter(
    :my_app_mint_crashes,
    {&MyApp.MintCrashReportFilter.filter/2, []}
  )
```

Two blunter settings also keep reports out, at a cost: `config :logger, handle_otp_reports: false` drops every OTP report including those of your own processes, and a Logger `level` of `:critical` drops every `:error` log.
