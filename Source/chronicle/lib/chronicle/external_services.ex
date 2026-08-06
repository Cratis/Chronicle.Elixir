# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ExternalServices do
  @moduledoc """
  Idiomatic API for registering external service definitions with Chronicle.

  External services let the Chronicle kernel talk to systems outside the
  event store — an HTTP API or a MsSql/PostgreSql database — under a name
  other kernel features (such as captures) can reference.

  ## Registration

      :ok =
        Chronicle.ExternalServices.register("payments-api", fn builder ->
          builder
          |> Chronicle.ExternalServices.DefinitionBuilder.http("https://payments.example.com")
          |> Chronicle.ExternalServices.DefinitionBuilder.with_bearer_token(
            System.fetch_env!("PAYMENTS_API_TOKEN")
          )
        end)

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
  """

  alias Chronicle.Connections.Connection
  alias Chronicle.ExternalServices.{Definition, DefinitionBuilder}
  alias Cratis.Chronicle.Contracts.ExternalServices.AddExternalServices
  alias Cratis.Chronicle.Contracts.ExternalServices.ExternalServices, as: ExternalServicesService

  @doc """
  Registers an external service.

  `configure` receives a `Chronicle.ExternalServices.DefinitionBuilder` and
  must return it (or a continuation of it) after configuring the endpoint.
  """
  @spec register(String.t(), (DefinitionBuilder.t() -> DefinitionBuilder.t()), keyword()) ::
          :ok | {:error, term()}
  def register(name, configure, opts \\ [])
      when is_binary(name) and is_function(configure, 1) and is_list(opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      definition =
        DefinitionBuilder.new()
        |> configure.()
        |> ensure_builder!(name)
        |> DefinitionBuilder.build(name, name)

      add_definitions(channel, config.event_store, [definition])
    end
  end

  defp add_definitions(channel, event_store, definitions) do
    request =
      struct(AddExternalServices,
        EventStore: event_store,
        ExternalServices: Enum.map(definitions, &Definition.to_proto/1)
      )

    case ExternalServicesService.Stub.add(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_builder!(%DefinitionBuilder{} = builder, _name), do: builder

  defp ensure_builder!(_other, name) do
    raise ArgumentError,
          "external service #{name} must return a Chronicle.ExternalServices.DefinitionBuilder"
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
