# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels do
  @moduledoc """
  Queries Chronicle read model instances.

  Read models are populated by reducers and projections. Use `get/3` to fetch
  the current state of a single read model instance by its key, or `all/2` to
  retrieve all instances.

  ## Usage

      {:ok, account} = Chronicle.ReadModels.get(MyApp.ReadModels.Account, "account-1")
      {:ok, accounts} = Chronicle.ReadModels.all(MyApp.ReadModels.Account)

  With explicit client:

      {:ok, account} = Chronicle.ReadModels.get(
        MyApp.ReadModels.Account,
        "account-1",
        client: :bank_chronicle
      )
  """

  alias Cratis.Chronicle.Contracts.ReadModels.{
    ReadModels,
    GetInstanceByKeyRequest,
    GetAllInstancesRequest
  }

  alias Chronicle.Connections.Connection

  @event_log_id "event-log"

  @doc """
  Fetches a read model instance by its key.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — the event sequence to project from (default: `"event-log"`)

  Returns `{:ok, model_struct}` on success, or `{:ok, nil}` if not found.
  """
  @spec get(module(), String.t(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  def get(model_module, key, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = model_module.__chronicle_read_model__(:id)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request = %GetInstanceByKeyRequest{
        EventStore: config.event_store,
        Namespace: namespace,
        ReadModelIdentifier: model_id,
        EventSequenceId: event_sequence_id,
        ReadModelKey: key,
        SessionId: ""
      }

      case ReadModels.Stub.get_instance_by_key(channel, request) do
        {:ok, response} ->
          json = Map.get(response, :ReadModel, "")

          case json do
            "" -> {:ok, nil}
            nil -> {:ok, nil}
            _ -> {:ok, decode_model(model_module, json)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns all instances of the given read model.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — the event sequence to project from (default: `"event-log"`)
  """
  @spec all(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def all(model_module, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = model_module.__chronicle_read_model__(:id)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request = %GetAllInstancesRequest{
        EventStore: config.event_store,
        Namespace: namespace,
        ReadModelIdentifier: model_id,
        EventSequenceId: event_sequence_id
      }

      case ReadModels.Stub.get_all_instances(channel, request) do
        {:ok, response} ->
          models =
            Map.get(response, :Instances, [])
            |> Enum.map(&decode_model(model_module, &1))
            |> Enum.filter(&(not is_nil(&1)))

          {:ok, models}

        {:error, reason} ->
          {:error, reason}
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

  defp decode_model(module, json) when is_binary(json) and json != "" do
    case Jason.decode(json) do
      {:ok, attrs} ->
        fields =
          attrs
          |> Enum.flat_map(fn {key, val} ->
            try do
              [{String.to_existing_atom(key), val}]
            rescue
              ArgumentError -> []
            end
          end)
          |> Enum.filter(fn {key, _} -> Map.has_key?(module.__struct__(), key) end)

        struct(module, fields)

      {:error, _} ->
        nil
    end
  end

  defp decode_model(_module, _), do: nil
end
