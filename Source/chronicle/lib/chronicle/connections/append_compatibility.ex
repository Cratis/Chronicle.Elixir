# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AppendCompatibility do
  @moduledoc false

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, ConnectionService}
  alias Cratis.Chronicle.Contracts.DescriptorSet

  # The contracts package's mix.exs reports 0.1.0 in downstream projects;
  # Hex's package metadata records the actual version of the installed contracts.
  @contracts_metadata Path.join(
                        Mix.Project.deps_paths()[:cratis_chronicle_contracts],
                        "hex_metadata.config"
                      )
  @external_resource @contracts_metadata
  @protocol_version (case :file.consult(@contracts_metadata) do
                       {:ok, metadata} ->
                         case List.keyfind(metadata, "version", 0) do
                           {"version", version} when is_binary(version) ->
                             version

                           _ ->
                             raise "contracts package must come from Hex with version metadata in #{@contracts_metadata}"
                         end

                       {:error, reason} ->
                         raise "contracts package must come from Hex; cannot read version metadata #{@contracts_metadata}: #{inspect(reason)}"
                     end)
  @client_version_path Path.expand("../../../VERSION", __DIR__)
  @external_resource @client_version_path
  @client_version @client_version_path |> File.read!() |> String.trim()

  @doc false
  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @spec check(%GRPC.Channel{}) :: :ok | {:error, term()}
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
      ProtocolVersion: @protocol_version,
      DescriptorSet: descriptor
    }

    case ConnectionService.Stub.check_compatibility(channel, request, timeout: 10_000) do
      {:ok, %{IsCompatible: true, Incompatibilities: []}} -> :ok
      {:ok, response} -> {:error, {:incompatible_server, response}}
      {:error, reason} -> {:error, {:compatibility_check_failed, reason}}
    end
  end
end
