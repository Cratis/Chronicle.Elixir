# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ResponseCrashRedaction do
  @moduledoc false

  # grpc 1.0.5 keeps request headers (the API key and the bearer token) in the state of
  # several processes: the Mint response process holds the whole stream, the Mint connection
  # process holds an HTTP/2 connection whose HPACK table stores the `api-key` header, and
  # `GRPC.Client.Connection` holds the channel. When one of them crashes, OTP reports its
  # state, last message and stacktrace arguments. A primary filter runs before any Logger
  # handler formats the event, including externally installed ones, so it covers every
  # report shape that carries those terms:
  #
  #   * `gen_server`, `gen_statem` and `gen_event` terminate reports,
  #   * `proc_lib` crash reports,
  #   * supervisor child_terminated, start_error and shutdown reports,
  #   * plain string and format events, scrubbed for remembered credential values.
  @filter_id :chronicle_mint_response_crash_redaction

  @report_origins [:gen_server, :gen_statem, :gen_event, :proc_lib, :supervisor]
  @text_levels [:emergency, :alert, :critical, :error, :warning]

  alias Chronicle.Connections.CredentialScrubber

  require Logger

  # Installing the filter is best effort: failing to install it must not stop the client.
  @spec install!() :: :ok
  def install! do
    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter/2, nil}) do
      :ok ->
        :ok

      {:error, {:already_exist, @filter_id}} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "cannot install gRPC crash report redaction, crash reports may contain " <>
            "request headers: #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc false
  def filter(
        %{msg: {:report, %{label: {:gen_server, :terminate}, state: state} = report}} = event,
        _config
      )
      when is_map(state) and is_map_key(state, :grpc_stream) do
    case state.grpc_stream do
      %GRPC.Client.Stream{} ->
        notice =
          "gRPC Mint response process terminated (#{reason_class(report)}); " <>
            "crash report suppressed to protect authentication headers"

        %{event | msg: {:string, notice}}

      _ ->
        scrub_report(event)
    end
  end

  def filter(%{msg: {:report, %{label: {origin, _}}}} = event, _config)
      when origin in @report_origins,
      do: scrub_report(event)

  def filter(%{level: level, msg: {:string, data}} = event, _config)
      when level in @text_levels do
    case CredentialScrubber.chardata(data) do
      ^data -> event
      scrubbed -> %{event | msg: {:string, scrubbed}}
    end
  end

  def filter(%{level: level, msg: {format, args}} = event, _config)
      when level in @text_levels and is_list(args) do
    case CredentialScrubber.term(args) do
      ^args -> event
      scrubbed -> %{event | msg: {format, scrubbed}}
    end
  end

  def filter(event, _config), do: event

  defp scrub_report(%{msg: {:report, report}} = event) do
    case CredentialScrubber.term(report) do
      ^report -> event
      scrubbed -> %{event | msg: {:report, scrubbed}}
    end
  end

  # Only the module or atom naming the failure is printed, never data from the report.
  defp reason_class(%{reason: reason}), do: class(reason)
  defp reason_class(_report), do: "unknown reason"

  defp class(%{__struct__: module}), do: inspect(module)
  defp class({reason, _detail}), do: class(reason)
  defp class(reason) when is_atom(reason), do: inspect(reason)
  defp class(_reason), do: "unknown reason"
end
