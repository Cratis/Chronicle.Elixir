# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ResponseCrashRedaction do
  @moduledoc false

  # grpc 1.0.5 retains the whole request stream, including its channel and
  # per-call headers, in the Mint response process state. A malformed trailer
  # can crash that process and OTP logs its state. A primary filter runs before
  # any Logger handler formats the report, including externally installed ones.
  @filter_id :chronicle_mint_response_crash_redaction

  @spec install!() :: :ok
  def install! do
    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter/2, nil}) do
      :ok -> :ok
      {:error, {:already_exist, @filter_id}} -> :ok
      {:error, reason} -> raise "cannot install gRPC crash report redaction: #{inspect(reason)}"
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
        event
    end
  end

  def filter(event, _config), do: event
end
