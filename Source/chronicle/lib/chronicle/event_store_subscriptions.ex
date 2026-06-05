# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptions do
  @moduledoc """
  Idiomatic API for working with Chronicle event store subscriptions.

  Event store subscriptions let one event store subscribe to events emitted from
  another event store's outbox. They can be registered imperatively, or declared
  as discoverable modules with `use Chronicle.EventStoreSubscriptions.Subscription`
  and auto-registered by `Chronicle.Client`.

  ## Discoverable subscriptions

      defmodule MyApp.EventStoreSubscriptions.DefaultAccountEvents do
        use Chronicle.EventStoreSubscriptions.Subscription,
          source_event_store: "default"

        alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

        @impl true
        def define(builder) do
          builder
          |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
          |> DefinitionBuilder.with_event_type(MyApp.Events.FundsDeposited)
        end
      end

  ## Imperative registration

      :ok =
        Chronicle.EventStoreSubscriptions.subscribe(
          "account-events-from-default",
          "default",
          fn builder ->
            builder
            |> Chronicle.EventStoreSubscriptions.DefinitionBuilder.with_event_type(
              MyApp.Events.AccountOpened
            )
          end
        )

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — accepted for consistency with other APIs and ignored here
  """

  alias Chronicle.Artifacts
  alias Chronicle.Connections.Connection
  alias Chronicle.EventStoreSubscriptions.{Definition, DefinitionBuilder}

  alias Cratis.Chronicle.Contracts.Observation.EventStoreSubscriptions.{
    AddEventStoreSubscriptions,
    EventStoreSubscriptions,
    RemoveEventStoreSubscriptions
  }

  @doc """
  Discovers event store subscription definitions from the configured client or
  loaded modules.
  """
  @spec discover(keyword()) :: [Definition.t()]
  def discover(opts \\ []) do
    opts
    |> subscription_modules()
    |> Enum.map(&build_definition(&1, opts))
  end

  @doc """
  Registers all discoverable event store subscriptions.
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
  Registers a single discoverable event store subscription module.
  """
  @spec register(module(), keyword()) :: :ok | {:error, term()}
  def register(subscription_module, opts)
      when is_list(opts) and is_atom(subscription_module) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      definition = build_definition(subscription_module, opts)
      add_definitions(channel, config.event_store, [definition])
    end
  end

  @doc """
  Registers an event store subscription imperatively using all available event
  types.
  """
  @spec subscribe(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe(subscription_id, source_event_store, opts)
      when is_binary(subscription_id) and is_binary(source_event_store) and is_list(opts) do
    subscribe(subscription_id, source_event_store, & &1, opts)
  end

  @doc """
  Registers an event store subscription imperatively.
  """
  @spec subscribe(
          String.t(),
          String.t(),
          (DefinitionBuilder.t() -> DefinitionBuilder.t()),
          keyword()
        ) :: :ok | {:error, term()}
  def subscribe(subscription_id, source_event_store, configure, opts \\ [])
      when is_binary(subscription_id) and is_binary(source_event_store) and
             is_function(configure, 1) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      builder =
        available_event_types(opts)
        |> DefinitionBuilder.new()
        |> configure.()
        |> ensure_builder!(subscription_id)

      definition = DefinitionBuilder.build(builder, subscription_id, source_event_store)
      add_definitions(channel, config.event_store, [definition])
    end
  end

  @doc """
  Removes an event store subscription by identifier.
  """
  @spec unsubscribe(String.t(), keyword()) :: :ok | {:error, term()}
  def unsubscribe(subscription_id, opts \\ []) when is_binary(subscription_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(RemoveEventStoreSubscriptions,
          TargetEventStore: config.event_store,
          SubscriptionIds: [subscription_id]
        )

      case EventStoreSubscriptions.Stub.remove(channel, request) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp add_definitions(channel, event_store, definitions) do
    request =
      struct(AddEventStoreSubscriptions,
        TargetEventStore: event_store,
        Subscriptions: Enum.map(definitions, &Definition.to_proto/1)
      )

    case EventStoreSubscriptions.Stub.add(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_definition(subscription_module, opts) do
    unless function_exported?(subscription_module, :__chronicle_event_store_subscription__, 1) do
      raise ArgumentError,
            "#{inspect(subscription_module)} is not a discoverable Chronicle event store subscription"
    end

    builder =
      available_event_types(opts)
      |> DefinitionBuilder.new()
      |> subscription_module.define()
      |> ensure_builder!(inspect(subscription_module))

    DefinitionBuilder.build(
      builder,
      subscription_module.__chronicle_event_store_subscription__(:id),
      subscription_module.__chronicle_event_store_subscription__(:source_event_store)
    )
  end

  defp ensure_builder!(%DefinitionBuilder{} = builder, _subscription_id), do: builder

  defp ensure_builder!(_other, subscription_id) do
    raise ArgumentError,
          "event store subscription #{subscription_id} must return a " <>
            "Chronicle.EventStoreSubscriptions.DefinitionBuilder"
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

  defp subscription_modules(opts) do
    case configured_client(opts) do
      %{event_store_subscriptions: subscriptions}
      when is_list(subscriptions) and subscriptions != [] ->
        subscriptions

      _ ->
        Artifacts.discover_loaded().event_store_subscriptions
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
end
