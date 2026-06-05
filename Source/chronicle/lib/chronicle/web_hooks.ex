# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks do
  @moduledoc """
  Idiomatic API for working with Chronicle webhooks.

  Webhooks let Chronicle push observed events to external HTTP endpoints. They
  can be registered imperatively, or declared as discoverable modules with
  `use Chronicle.WebHooks.Webhook` and auto-registered by `Chronicle.Client`.

  ## Discoverable webhooks

      defmodule MyApp.WebHooks.AccountEvents do
        use Chronicle.WebHooks.Webhook,
          target_url: "https://example.com/chronicle/webhooks"

        alias Chronicle.WebHooks.DefinitionBuilder

        @impl true
        def define(builder) do
          builder
          |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
          |> DefinitionBuilder.with_bearer_token(System.fetch_env!("WEBHOOK_TOKEN"))
        end
      end

  ## Imperative registration

      :ok =
        Chronicle.WebHooks.register(
          "account-events",
          "https://example.com/chronicle/webhooks",
          fn builder ->
            builder
            |> Chronicle.WebHooks.DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
            |> Chronicle.WebHooks.DefinitionBuilder.with_header("x-source", "my-app")
          end
        )

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — accepted for consistency with other APIs and ignored here
  """

  alias Chronicle.Artifacts
  alias Chronicle.Connections.Connection
  alias Chronicle.WebHooks.{Definition, DefinitionBuilder}

  alias Cratis.Chronicle.Contracts.Observation.Webhooks.{
    AddWebhooks,
    GetWebhooksRequest,
    RemoveWebhooks,
    Webhooks
  }

  @doc """
  Discovers webhook definitions from the configured client or loaded modules.
  """
  @spec discover(keyword()) :: [Definition.t()]
  def discover(opts \\ []) do
    opts
    |> webhook_modules()
    |> Enum.map(&build_definition(&1, opts))
  end

  @doc """
  Registers all discoverable webhooks.
  """
  @spec register_discovered(keyword()) :: :ok | {:error, term()}
  def register_discovered(opts \\ []) do
    definitions = discover(opts)

    if Enum.empty?(definitions) do
      :ok
    else
      with {:ok, channel, config} <- resolve_channel(opts) do
        add_definitions(channel, config.event_store, definitions)
      end
    end
  end

  @doc """
  Registers a single discoverable webhook module.
  """
  @spec register(module(), keyword()) :: :ok | {:error, term()}
  def register(webhook_module, opts \\ []) when is_list(opts) and is_atom(webhook_module) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      definition = build_definition(webhook_module, opts)
      add_definitions(channel, config.event_store, [definition])
    end
  end

  @doc """
  Registers a webhook imperatively.
  """
  @spec register(
          String.t(),
          String.t(),
          (DefinitionBuilder.t() -> DefinitionBuilder.t()),
          keyword()
        ) ::
          :ok | {:error, term()}
  def register(webhook_id, target_url, configure, opts \\ [])
      when is_binary(webhook_id) and is_binary(target_url) and is_function(configure, 1) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      builder =
        available_event_types(opts)
        |> DefinitionBuilder.new()
        |> configure.()
        |> ensure_builder!(webhook_id)

      definition = DefinitionBuilder.build(builder, webhook_id, target_url)
      add_definitions(channel, config.event_store, [definition])
    end
  end

  @doc """
  Gets all registered webhooks for the current event store.
  """
  @spec all(keyword()) :: {:ok, [Definition.t()]} | {:error, term()}
  def all(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = struct(GetWebhooksRequest, EventStore: config.event_store)

      case Webhooks.Stub.get_webhooks(channel, request) do
        {:ok, response} ->
          webhooks =
            response
            |> Map.get(:items, Map.get(response, :Items, []))
            |> Enum.map(&Definition.from_proto/1)

          {:ok, webhooks}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Removes a webhook by identifier.
  """
  @spec remove(String.t(), keyword()) :: :ok | {:error, term()}
  def remove(webhook_id, opts \\ []) when is_binary(webhook_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(RemoveWebhooks,
          EventStore: config.event_store,
          Webhooks: [webhook_id]
        )

      case Webhooks.Stub.remove(channel, request) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp add_definitions(channel, event_store, definitions) do
    request =
      struct(AddWebhooks,
        EventStore: event_store,
        Owner: observer_owner(:client),
        Webhooks: Enum.map(definitions, &Definition.to_proto/1)
      )

    case Webhooks.Stub.add(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_definition(webhook_module, opts) do
    unless function_exported?(webhook_module, :__chronicle_webhook__, 1) do
      raise ArgumentError, "#{inspect(webhook_module)} is not a discoverable Chronicle webhook"
    end

    builder =
      available_event_types(opts)
      |> DefinitionBuilder.new()
      |> webhook_module.define()
      |> ensure_builder!(inspect(webhook_module))

    builder =
      case webhook_module.__chronicle_webhook__(:event_sequence_id) do
        nil -> builder
        event_sequence_id -> DefinitionBuilder.on_event_sequence(builder, event_sequence_id)
      end

    DefinitionBuilder.build(
      builder,
      webhook_module.__chronicle_webhook__(:id),
      webhook_module.__chronicle_webhook__(:target_url)
    )
  end

  defp ensure_builder!(%DefinitionBuilder{} = builder, _webhook_id), do: builder

  defp ensure_builder!(_other, webhook_id) do
    raise ArgumentError,
          "webhook #{webhook_id} must return a Chronicle.WebHooks.DefinitionBuilder"
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

  defp webhook_modules(opts) do
    case configured_client(opts) do
      %{webhooks: webhooks} when is_list(webhooks) and webhooks != [] -> webhooks
      _ -> Artifacts.discover_loaded().webhooks
    end
  end

  defp available_event_types(opts) do
    case configured_client(opts) do
      %{event_types: event_types} when is_list(event_types) and event_types != [] -> event_types
      _ -> Artifacts.discover_loaded().event_types
    end
    |> Enum.uniq()
  end

  defp configured_client(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    Chronicle.Client.config(client)
  rescue
    _ -> nil
  end

  defp observer_owner(:client), do: 1
end
