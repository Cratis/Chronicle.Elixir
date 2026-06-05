# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.Coordinator do
  @moduledoc false

  # Drives the ordered registration of base artifacts on every (re)connect,
  # mirroring the C# client's EventStore.RegisterAll. It subscribes to the
  # connection lifecycle and, on the `:connected` phase, ensures the event store
  # and namespace exist and registers event types, constraints, read models
  # (including reducer read-model/observer definitions) and projections. Only
  # after this base registration succeeds does it advance the lifecycle to the
  # `:registered` phase — the signal that lets reactors, reducers, seeders and
  # the webhook/subscription registrars safely register. This ordering is what
  # prevents observers from registering their observation streams before their
  # server-side definitions exist.

  use GenServer, restart: :permanent

  require Logger

  alias Chronicle.Connections.{Connection, Lifecycle}
  alias Chronicle.Events.Constraints
  alias Chronicle.Events.EventTypes
  alias Chronicle.Schemas.JsonSchemaGenerator

  alias Cratis.Chronicle.Contracts.{EventStores, Namespaces, EnsureEventStore, EnsureNamespace}

  alias Cratis.Chronicle.Contracts.Projections.{
    Projections,
    RegisterRequest,
    ProjectionDefinition,
    FromDefinition,
    JoinDefinition,
    RemovedWithDefinition,
    FromEveryDefinition,
    KeyValuePair_EventType_FromDefinition,
    KeyValuePair_EventType_JoinDefinition,
    KeyValuePair_EventType_RemovedWithDefinition
  }

  alias Cratis.Chronicle.Contracts.Projections.EventType, as: ProtoEventType

  alias Cratis.Chronicle.Contracts.ReadModels.{
    ReadModels,
    RegisterManyRequest,
    ReadModelDefinition,
    ReadModelType,
    SinkDefinition
  }

  alias Bcl.Guid, as: BclGuid

  # MongoDB sink type ID: "22202c41-2be1-4547-9c00-f0b1f797fd75"
  # Computed from .NET Guid.ToByteArray() split into lo/hi fixed64 little-endian
  defp mongodb_sink_type_id, do: struct(BclGuid, lo: 0x45472BE122202C41, hi: 0x75FD97F7B1F0009C)

  @retry_delay 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %{
      connection: Keyword.fetch!(opts, :connection),
      lifecycle: Keyword.get(opts, :lifecycle),
      event_store: Keyword.fetch!(opts, :event_store),
      namespace: Keyword.get(opts, :namespace, "Default"),
      event_types: Keyword.get(opts, :event_types, []),
      migrations: Keyword.get(opts, :migrations, []),
      read_models: Keyword.get(opts, :read_models, []),
      reducers: Keyword.get(opts, :reducers, []),
      projections: Keyword.get(opts, :projections, []),
      register_fun: Keyword.get(opts, :register_fun, &default_register/1),
      retry_timer: nil,
      registered_done?: false
    }

    if state.lifecycle do
      Lifecycle.subscribe(state.lifecycle)
    else
      # Standalone (no lifecycle): register immediately, as before.
      send(self(), :register)
    end

    {:ok, state}
  end

  @impl true
  def handle_info({:chronicle_lifecycle, :connected, _connection_id}, state) do
    cancel_timer(state.retry_timer)
    send(self(), :register)
    {:noreply, %{state | retry_timer: nil, registered_done?: false}}
  end

  def handle_info({:chronicle_lifecycle, :disconnected, _connection_id}, state) do
    cancel_timer(state.retry_timer)
    {:noreply, %{state | retry_timer: nil, registered_done?: false}}
  end

  def handle_info({:chronicle_lifecycle, :registered, _connection_id}, state) do
    # We are the source of this transition — nothing to do.
    {:noreply, state}
  end

  def handle_info(:register, state) do
    case state.register_fun.(state) do
      :ok ->
        if state.lifecycle, do: Lifecycle.registered(state.lifecycle)
        {:noreply, %{state | registered_done?: true, retry_timer: nil}}

      {:error, reason} ->
        Logger.warning(
          "Chronicle registration failed: #{inspect(reason)}, retrying in #{@retry_delay}ms"
        )

        timer = Process.send_after(self(), :register, @retry_delay)
        {:noreply, %{state | retry_timer: timer}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp default_register(state) do
    case Connection.channel(state.connection) do
      {:ok, channel} -> register_all(channel, state)
      {:error, _} = error -> error
    end
  end

  defp register_all(channel, state) do
    # Collect event types from projection read models
    read_model_event_types =
      state.read_models
      |> Enum.flat_map(fn rm ->
        (rm.__chronicle_read_model__(:from) |> Enum.map(&elem(&1, 0))) ++
          (rm.__chronicle_read_model__(:join) |> Enum.map(&elem(&1, 0))) ++
          (rm.__chronicle_read_model__(:removed_with) |> Enum.map(&elem(&1, 0)))
      end)

    # Also collect event types from reducers
    reducer_event_types =
      state.reducers
      |> Enum.flat_map(fn r -> r.__chronicle_reducer__(:handles) end)

    # Collect event types from declarative projections
    declarative_projection_event_types =
      state.projections
      |> Enum.flat_map(fn proj ->
        (proj.__chronicle_projection__(:from) |> Enum.map(&elem(&1, 0))) ++
          (proj.__chronicle_projection__(:join) |> Enum.map(&elem(&1, 0))) ++
          (proj.__chronicle_projection__(:removed_with) |> Enum.map(&elem(&1, 0)))
      end)

    all_event_types =
      Enum.uniq(
        state.event_types ++
          read_model_event_types ++
          reducer_event_types ++
          declarative_projection_event_types
      )

    with :ok <- ensure_event_store(channel, state.event_store),
         :ok <- ensure_namespace(channel, state.event_store, state.namespace),
         :ok <-
           EventTypes.register(channel, state.event_store, all_event_types, state.migrations),
         :ok <- register_constraints(channel, state, all_event_types),
         :ok <- register_read_models(channel, state),
         :ok <- register_projections(channel, state) do
      :ok
    end
  end

  defp ensure_event_store(channel, event_store) do
    case EventStores.Stub.ensure(channel, struct(EnsureEventStore, Name: event_store)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:ensure_event_store, reason}}
    end
  end

  defp ensure_namespace(channel, event_store, namespace) do
    case Namespaces.Stub.ensure(
           channel,
           struct(EnsureNamespace, EventStore: event_store, Name: namespace)
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:ensure_namespace, reason}}
    end
  end

  defp register_constraints(channel, state, event_types) do
    constraints = Constraints.from_event_types(event_types)

    case Constraints.register(channel, state.event_store, constraints) do
      :ok -> :ok
      {:error, reason} -> {:error, {:register_constraints, reason}}
    end
  end

  defp register_read_models(channel, state) do
    projection_definitions =
      state.read_models
      |> Enum.filter(& &1.__chronicle_read_model__(:has_projection?))
      |> Enum.map(fn rm ->
        model_id = rm.__chronicle_read_model__(:id)

        struct(ReadModelDefinition,
          Type: struct(ReadModelType, Identifier: model_id, Generation: 1),
          ContainerName: model_id,
          DisplayName: model_id,
          Sink:
            struct(SinkDefinition,
              ConfigurationId: struct(BclGuid),
              TypeId: mongodb_sink_type_id()
            ),
          Schema: generate_read_model_schema(rm),
          ObserverType: 2,
          ObserverIdentifier: model_id,
          Owner: 2,
          Source: 1
        )
      end)

    reducer_definitions =
      state.reducers
      |> Enum.map(fn reducer_module ->
        model_module = reducer_module.__chronicle_reducer__(:model)
        model_id = model_module.__chronicle_read_model__(:id)
        reducer_id = reducer_module.__chronicle_reducer__(:id)

        struct(ReadModelDefinition,
          Type: struct(ReadModelType, Identifier: model_id, Generation: 1),
          ContainerName: model_id,
          DisplayName: model_id,
          Sink:
            struct(SinkDefinition,
              ConfigurationId: struct(BclGuid),
              TypeId: mongodb_sink_type_id()
            ),
          Schema: generate_read_model_schema(model_module),
          ObserverType: 1,
          ObserverIdentifier: reducer_id,
          Owner: 2,
          Source: 1
        )
      end)

    declarative_projection_definitions =
      state.projections
      |> Enum.map(fn proj ->
        projection_id = proj.__chronicle_projection__(:id)
        model_module = proj.__chronicle_projection__(:model)
        model_id = model_module.__chronicle_read_model__(:id)

        struct(ReadModelDefinition,
          Type: struct(ReadModelType, Identifier: model_id, Generation: 1),
          ContainerName: model_id,
          DisplayName: model_id,
          Sink:
            struct(SinkDefinition,
              ConfigurationId: struct(BclGuid),
              TypeId: mongodb_sink_type_id()
            ),
          Schema: generate_read_model_schema(model_module),
          ObserverType: 2,
          ObserverIdentifier: projection_id,
          Owner: 2,
          Source: 1
        )
      end)

    all_definitions = projection_definitions ++ reducer_definitions ++ declarative_projection_definitions

    if Enum.empty?(all_definitions) do
      :ok
    else
      request =
        struct(RegisterManyRequest,
          EventStore: state.event_store,
          Owner: 2,
          ReadModels: all_definitions,
          Source: 1
        )

      case ReadModels.Stub.register_many(channel, request) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:register_read_models, reason}}
      end
    end
  end

  # Builds the initial model state JSON from struct defaults.
  # Numeric/boolean defaults (like balance: 0) must be non-null in the JSON so that
  # Chronicle's PerformAdd/PerformSubtract receive 0.0 instead of null — Convert.ChangeType
  # throws for null double (a non-nullable CLR value type).
  defp initial_model_state(module) do
    if function_exported?(module, :__struct__, 0) do
      defaults =
        module.__struct__()
        |> Map.to_list()
        |> Enum.reject(fn {k, _} -> k == :__struct__ end)
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

      Jason.encode!(defaults)
    else
      "{}"
    end
  end

  # Read model state is stored with its struct field names (snake_case), so the
  # schema uses identity key transform. PII-adorned fields carry compliance
  # metadata into the schema.
  defp generate_read_model_schema(module) do
    JsonSchemaGenerator.generate(module, key_transform: :identity)
  end

  defp register_projections(_channel, %{read_models: [], projections: []}), do: :ok

  defp register_projections(channel, state) do
    model_bound_definitions =
      state.read_models
      |> Enum.filter(& &1.__chronicle_read_model__(:has_projection?))
      |> Enum.map(&build_projection_definition/1)

    declarative_definitions =
      Enum.map(state.projections, &build_declarative_projection_definition/1)

    definitions = model_bound_definitions ++ declarative_definitions

    if Enum.empty?(definitions) do
      :ok
    else
      request =
        struct(RegisterRequest,
          EventStore: state.event_store,
          Owner: 1,
          Projections: definitions
        )

      case Projections.Stub.register(channel, request) do
        {:ok, _} ->
          Logger.info("Registered #{length(definitions)} projection(s) with Chronicle")
          :ok

        {:error, reason} ->
          {:error, {:register_projections, reason}}
      end
    end
  end

  defp build_projection_definition(read_model_module) do
    identifier = read_model_module.__chronicle_read_model__(:id)
    model_name = identifier

    from_entries =
      read_model_module.__chronicle_read_model__(:from)
      |> Enum.map(fn {event_module, opts} ->
        properties = build_properties(opts)
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        parent_key = Keyword.get(opts, :parent_key, "")

        struct(KeyValuePair_EventType_FromDefinition,
          Key: proto_event_type(event_module),
          Value:
            struct(FromDefinition,
              Key: key,
              Properties: properties,
              ParentKey: parent_key
            )
        )
      end)

    join_entries =
      read_model_module.__chronicle_read_model__(:join)
      |> Enum.map(fn {event_module, opts} ->
        properties = build_properties(opts)
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        on = opts |> Keyword.fetch!(:on) |> to_string()

        struct(KeyValuePair_EventType_JoinDefinition,
          Key: proto_event_type(event_module),
          Value:
            struct(JoinDefinition,
              On: on,
              Key: key,
              Properties: properties
            )
        )
      end)

    removed_with_entries =
      read_model_module.__chronicle_read_model__(:removed_with)
      |> Enum.map(fn {event_module, opts} ->
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        parent_key = Keyword.get(opts, :parent_key, "")

        struct(KeyValuePair_EventType_RemovedWithDefinition,
          Key: proto_event_type(event_module),
          Value: struct(RemovedWithDefinition, Key: key, ParentKey: parent_key)
        )
      end)

    from_every =
      case read_model_module.__chronicle_read_model__(:from_every) do
        [] ->
          nil

        [opts | _] ->
          struct(FromEveryDefinition,
            Properties: build_properties(opts),
            IncludeChildren: Keyword.get(opts, :include_children, false)
          )
      end

    struct(ProjectionDefinition,
      Identifier: identifier,
      ReadModel: model_name,
      EventSequenceId: "event-log",
      IsActive: true,
      IsRewindable: true,
      From: from_entries,
      Join: join_entries,
      RemovedWith: removed_with_entries,
      All: from_every,
      InitialModelState: initial_model_state(read_model_module)
    )
  end

  defp build_declarative_projection_definition(projection_module) do
    projection_id = projection_module.__chronicle_projection__(:id)
    model_module = projection_module.__chronicle_projection__(:model)
    model_id = model_module.__chronicle_read_model__(:id)

    from_entries =
      projection_module.__chronicle_projection__(:from)
      |> Enum.map(fn {event_module, opts} ->
        properties = build_properties(opts)
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        parent_key = Keyword.get(opts, :parent_key, "")

        struct(KeyValuePair_EventType_FromDefinition,
          Key: proto_event_type(event_module),
          Value:
            struct(FromDefinition,
              Key: key,
              Properties: properties,
              ParentKey: parent_key
            )
        )
      end)

    join_entries =
      projection_module.__chronicle_projection__(:join)
      |> Enum.map(fn {event_module, opts} ->
        properties = build_properties(opts)
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        on = opts |> Keyword.fetch!(:on) |> to_string()

        struct(KeyValuePair_EventType_JoinDefinition,
          Key: proto_event_type(event_module),
          Value:
            struct(JoinDefinition,
              On: on,
              Key: key,
              Properties: properties
            )
        )
      end)

    removed_with_entries =
      projection_module.__chronicle_projection__(:removed_with)
      |> Enum.map(fn {event_module, opts} ->
        key = opts |> Keyword.get(:key, :event_source_id) |> resolve_key_expression()
        parent_key = Keyword.get(opts, :parent_key, "")

        struct(KeyValuePair_EventType_RemovedWithDefinition,
          Key: proto_event_type(event_module),
          Value: struct(RemovedWithDefinition, Key: key, ParentKey: parent_key)
        )
      end)

    from_every =
      case projection_module.__chronicle_projection__(:from_every) do
        [] ->
          nil

        [opts | _] ->
          struct(FromEveryDefinition,
            Properties: build_properties(opts),
            IncludeChildren: Keyword.get(opts, :include_children, false)
          )
      end

    struct(ProjectionDefinition,
      Identifier: projection_id,
      ReadModel: model_id,
      EventSequenceId: "event-log",
      IsActive: true,
      IsRewindable: true,
      From: from_entries,
      Join: join_entries,
      RemovedWith: removed_with_entries,
      All: from_every,
      InitialModelState: initial_model_state(model_module)
    )
  end

  # Converts set/add/subtract/count opts into a Chronicle properties map.
  # The keys are read model field names (strings), the values are
  # Chronicle property expressions.
  defp build_properties(opts) do
    set_props =
      opts
      |> Keyword.get(:set, [])
      |> Enum.map(fn {field, expr} ->
        {to_string(field), resolve_expression(expr)}
      end)

    add_props =
      opts
      |> Keyword.get(:add, [])
      |> Enum.map(fn {field, expr} ->
        {to_string(field), "$add(#{resolve_expression(expr)})"}
      end)

    subtract_props =
      opts
      |> Keyword.get(:subtract, [])
      |> Enum.map(fn {field, expr} ->
        {to_string(field), "$subtract(#{resolve_expression(expr)})"}
      end)

    count_fields =
      case Keyword.get(opts, :count) do
        nil -> []
        field when is_atom(field) -> [{to_string(field), "$count"}]
        fields when is_list(fields) -> Enum.map(fields, fn f -> {to_string(f), "$count"} end)
      end

    (set_props ++ add_props ++ subtract_props ++ count_fields) |> Map.new()
  end

  defp resolve_expression(atom) when is_atom(atom) do
    case atom do
      :event_source_id -> "$eventSourceId"
      :occurred -> "$occurred"
      _ -> Atom.to_string(atom)
    end
  end

  defp resolve_expression(int) when is_integer(int), do: "$value(#{int})"
  defp resolve_expression(str) when is_binary(str), do: str

  defp resolve_key_expression(expr), do: resolve_expression(expr)

  defp proto_event_type(event_module) do
    struct(ProtoEventType,
      Id: event_module.__chronicle_event_type__(:id),
      Generation: event_module.__chronicle_event_type__(:generation)
    )
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
