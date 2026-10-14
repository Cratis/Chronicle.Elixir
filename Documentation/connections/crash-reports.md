---
title: Keep credentials out of crash reports
description: When gRPC and Mint crash reports can print your API key or bearer token, and the production Logger setup that keeps them out of shipped logs.
---

The client authenticates every call with an API key or an OAuth bearer token, sent as request headers. The gRPC and Mint libraries underneath it keep those headers in process state. When one of those processes crashes, OTP writes its state, last message and stacktrace arguments to the log at `:error` level, so a crash report can contain your credentials in clear text. Chronicle's own processes hide their credentials from crash reports. The client also installs a primary Logger filter that redacts the one dependency crash report shape it can intercept generically; the processes covered below remain a risk the filter in this page still protects.

## What the client already redacts

The `StreamResponseProcess` state holds the whole `%GRPC.Client.Stream{}`, including the channel headers (the `api-key` header) and the per-call `authorization` header. A malformed `grpc-status` trailer from the server is one trigger: it raises in grpc and, left alone, prints that state. `Connection.connect/2` installs a primary Logger filter (`Chronicle.Connections.ResponseCrashRedaction`) that recognizes this specific termination report shape and replaces it with a one-line notice before any handler formats it, so neither the API key nor the bearer token reaches your logs for this crash.

## What can still leak, and when

A report is written only when one of these processes crashes. The credentials can still appear in:

- The `ConnectionProcess` state and arguments. Mint's HTTP/2 connection keeps the headers it has sent in its HPACK encode table, and `api-key` is not in the static table, so the value is stored there.
- The `GRPC.Client.Connection` state, which holds the channel and its headers.

The client always sends `enable_push: false` to Mint. That removes the route where a server `PUSH_PROMISE` frame crashes `ConnectionProcess`, but the other crashes above remain possible. The recommended production Logger configuration below still applies to them.

## Recommended production Logger configuration

Keep crash reports from these processes out of shipped logs with a primary Logger filter. A primary filter runs before any handler formats the event, so it covers the console, files and any handler you add. This filter replaces a matching report with a one-line notice, so the crash stays visible in your logs without the credentials:

```elixir
defmodule MyApp.GrpcCrashReportFilter do
  @moduledoc false

  @notice "Report of a gRPC client process crash suppressed: it can contain credentials"
  @prefixes ["Elixir.GRPC.Client", "Elixir.GRPC.Channel", "Elixir.Mint."]

  def filter(%{msg: {:report, report}} = event, _extra) do
    if sensitive?(report), do: %{event | msg: {:string, @notice}}, else: :ignore
  end

  def filter(_event, _extra), do: :ignore

  defp sensitive?(atom) when is_atom(atom) do
    name = Atom.to_string(atom)
    Enum.any?(@prefixes, &String.starts_with?(name, &1))
  end

  defp sensitive?(%{} = map), do: map |> Map.to_list() |> sensitive?()
  defp sensitive?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> sensitive?()
  defp sensitive?([head | tail]), do: sensitive?(head) or sensitive?(tail)
  defp sensitive?(_other), do: false
end
```

Install it when your application starts, before you start the Chronicle client:

```elixir
def start(_type, _args) do
  :ok =
    :logger.add_primary_filter(
      :chronicle_credentials,
      {&MyApp.GrpcCrashReportFilter.filter/2, []}
    )

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

The filter matches any report that mentions a gRPC client, channel or Mint module, in its state, last message or stacktrace. That includes crashes of other processes that use Mint, such as an HTTP client. It handles the `gen_server` termination report and the `proc_lib` crash report alike. It does not look at messages your own code builds with `Logger.error/1`.

The filter only covers crash reports. When a linked process exits, grpc and the Chronicle client log its exit reason as a plain warning string, and the filter does not inspect those. If such a reason carries the connection state, the credentials can still reach the log, so restrict who can read production logs until the upstream fix described below ships.

Also keep these Logger settings, which are the defaults:

```elixir
config :logger, handle_sasl_reports: false
```

With `handle_sasl_reports: true`, Logger also prints the `proc_lib` crash report for the same process, which can repeat the credentials. The filter above catches it too, but production does not need it.

Two blunter settings also keep these reports out, but at a cost you should weigh first:

- `config :logger, handle_otp_reports: false` drops every OTP report, including the termination reports of your own processes.
- A Logger `level` of `:critical` drops every `:error` log.

Both keys exist in every Elixir version the client supports (1.18 and later), as does `:logger.add_primary_filter/2`. The filter is installed at runtime and does not survive a restart of the `:logger` application, so treat it as a safety net rather than a guarantee. Also restrict who can read production logs, and rotate an API key or client secret that has appeared in one.

## The complete fix is upstream

A filter only hides the symptom. The complete fix is in the `grpc` library: implementing `format_status/1` on `StreamResponseProcess`, `ConnectionProcess` and `GRPC.Client.Connection` so that request headers are redacted from crash reports, and not crashing on a malformed `grpc-status`. The client's own filter above covers the `StreamResponseProcess` shape today, but it is a client-side workaround for one report, not the upstream fix for all three processes. It is tracked in [Cratis/Chronicle.Elixir#79](https://github.com/Cratis/Chronicle.Elixir/issues/79). When a grpc release contains it, the client will require that release and the remaining guidance on this page will no longer be needed.
