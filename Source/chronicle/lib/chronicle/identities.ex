# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Identities do
  @moduledoc """
  Manager operations for identities known to Chronicle.

  Distinct from `Chronicle.Identity`, which represents a single identity value
  travelling with a state change; this module performs administrative
  operations against the identities the kernel has observed.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
  """

  alias Chronicle.Connections.Connection
  alias Cratis.Chronicle.Contracts.Identities.Identities, as: IdentitiesService
  alias Cratis.Chronicle.Contracts.Identities.RenameIdentityRequest

  @doc """
  Renames the name of an identity, identified by its subject.

  The subject is the stable identifier of the identity - the name is the
  display name and can change over time, for instance when a person changes
  their name. Renaming an identity affects every event and read model that
  refers to the identity, as the name is resolved from the identity itself
  and not stored with what refers to it.
  """
  @spec rename(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def rename(subject, name, opts \\ [])
      when is_binary(subject) and is_binary(name) and is_list(opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      request =
        struct(RenameIdentityRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          Subject: subject,
          Name: name
        )

      case IdentitiesService.Stub.rename_identity(channel, request) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case Connection.channel(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end
end
