# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStores do
  @moduledoc """
  Lists event stores and namespaces from the Chronicle kernel.

  This mirrors the TypeScript client surface for event-store discovery in an
  idiomatic Elixir API.
  """

  alias Cratis.Chronicle.Contracts.{EventStores, GetNamespacesRequest, Namespaces}
  alias Chronicle.Connections.Connection

  @doc """
  Returns all event store names.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
  """
  @spec get_all(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def get_all(opts \\ []) do
    with {:ok, channel, _config} <- resolve_channel(opts),
         {:ok, response} <-
           EventStores.Stub.get_event_stores(channel, %Google.Protobuf.Empty{}) do
      {:ok, items_from_response(response)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns all namespaces for an event store.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:event_store` — event store name (defaults to the configured client event store)
  """
  @spec get_namespaces(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def get_namespaces(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts),
         {:ok, response} <-
           Namespaces.Stub.get_namespaces(
             channel,
             struct(GetNamespacesRequest,
               EventStore: Keyword.get(opts, :event_store, config.event_store)
             )
           ) do
      {:ok, items_from_response(response)}
    else
      {:error, reason} -> {:error, reason}
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

  defp items_from_response(response) do
    response
    |> Map.get(:Items, Map.get(response, :items, []))
    |> Enum.map(fn
      item when is_binary(item) -> item
      %{Name: name} when is_binary(name) -> name
      %{name: name} when is_binary(name) -> name
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
  end
end
