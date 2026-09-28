# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AppendCompatibility do
  @moduledoc false

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, ConnectionService}
  alias Cratis.Chronicle.Contracts.DescriptorSet

  @client_version_path Path.expand("../../../VERSION", __DIR__)
  @external_resource @client_version_path
  @client_version @client_version_path |> File.read!() |> String.trim()

  @doc false
  @spec protocol_version() :: String.t()
  def protocol_version, do: DescriptorSet.protocol_version()

  @spec check(struct()) :: :ok | {:error, term()}
  def check(channel) do
    case DescriptorSet.bytes() do
      <<>> -> {:error, :missing_contract_descriptor}
      descriptor -> check_descriptor(channel, descriptor)
    end
  end

  defp check_descriptor(channel, descriptor) do
    request = %CompatibilityRequest{
      ClientType: "Elixir",
      ClientVersion: @client_version,
      ProtocolVersion: protocol_version(),
      DescriptorSet: descriptor
    }

    case ConnectionService.Stub.check_compatibility(channel, request, timeout: 10_000) do
      {:ok, %{IsCompatible: true, Incompatibilities: []}} -> :ok
      {:ok, response} -> {:error, {:incompatible_server, response}}
      {:error, reason} -> {:error, {:compatibility_check_failed, reason}}
    end
  end
end
