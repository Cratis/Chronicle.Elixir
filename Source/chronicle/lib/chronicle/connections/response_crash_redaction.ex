# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ResponseCrashRedaction do
  @moduledoc false

  # grpc 1.0.5 retains the whole request stream, including its channel and
  # per-call headers, in the Mint response process state. A malformed trailer
  # can crash that process and OTP logs its state. A primary filter runs before
  # any Logger handler formats the report, including externally installed ones.
  @filter_id :chronicle_mint_response_crash_redaction

  require Logger

  @redacted :"[redacted: contains a gRPC stream]"

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
        %{msg: {:report, %{label: {:gen_server, :terminate}, state: state}}} = event,
        _config
      )
      when is_map(state) and is_map_key(state, :grpc_stream) do
    case state.grpc_stream do
      %GRPC.Client.Stream{} ->
        %{
          event
          | msg:
              {:string,
               "gRPC Mint response process terminated; crash report suppressed to protect authentication headers"}
        }

      _ ->
        redact_fields(event)
    end
  end

  # A crash while handling a message can carry the stream (and its authentication headers)
  # in the message being handled or in the exit reason, even when the state does not.
  def filter(%{msg: {:report, %{label: {:gen_server, :terminate}}}} = event, _config),
    do: redact_fields(event)

  def filter(event, _config), do: event

  defp redact_fields(%{msg: {:report, report}} = event) do
    redacted =
      Enum.reduce([:last_message, :reason], report, fn key, acc ->
        if Map.has_key?(acc, key) and carries_stream?(Map.get(acc, key)),
          do: Map.put(acc, key, @redacted),
          else: acc
      end)

    if redacted == report, do: event, else: %{event | msg: {:report, redacted}}
  end

  defp carries_stream?(%GRPC.Client.Stream{}), do: true
  defp carries_stream?(%GRPC.Channel{headers: headers}) when headers not in [nil, []], do: true

  defp carries_stream?(%_{} = struct), do: struct |> Map.from_struct() |> carries_stream?()
  defp carries_stream?(map) when is_map(map), do: map |> Map.values() |> carries_stream?()

  defp carries_stream?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> carries_stream?()

  defp carries_stream?(list) when is_list(list), do: carries_stream_in_list?(list)
  defp carries_stream?(_other), do: false

  # Improper lists (from stack traces and iodata) are walked without crashing.
  defp carries_stream_in_list?([head | tail]),
    do: carries_stream?(head) or carries_stream_in_list?(tail)

  defp carries_stream_in_list?([]), do: false
  defp carries_stream_in_list?(improper), do: carries_stream?(improper)
end
