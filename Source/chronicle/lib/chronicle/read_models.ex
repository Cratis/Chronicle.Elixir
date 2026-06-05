# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels do
  @moduledoc """
  Idiomatic Elixir interface for Chronicle read models.

  Read models are the query side of Chronicle. They are produced by projections
  and reducers and can be queried in two complementary ways:

  - `get/3`, `get_instance_by_id/3`, `all/2`, and `get_instances/2` replay the
    configured event sequence in the same style as the C# and TypeScript
    `IReadModels` APIs.
  - `query/2` queries the materialized read-model container directly for paging
    and occurrence-oriented inspection.

  The module also exposes helper queries for metadata and history:

  - `snapshots/3` / `get_snapshots_by_id/3`
  - `occurrences/2` / `get_occurrences/2`
  - `definitions/1` / `get_definitions/1`

  ## Common options

  Most functions accept these options:

  - `:client` — the client name (default: `Chronicle.Client`)
  - `:namespace` — overrides the client's configured namespace
  - `:event_sequence_id` — event sequence identifier (default: `"event-log"`)

  ## Single instance lookup

      {:ok, account} = Chronicle.ReadModels.get(MyApp.ReadModels.Account, "account-1")
      {:ok, account} = Chronicle.ReadModels.get_instance_by_id(MyApp.ReadModels.Account, "account-1")

  Use `:session_id` when reading from a dehydrated or session-specific projection:

      {:ok, account} =
        Chronicle.ReadModels.get_instance_by_id(
          MyApp.ReadModels.Account,
          "account-1",
          session_id: "session-42"
        )

  ## Replay all instances

      {:ok, accounts} = Chronicle.ReadModels.all(MyApp.ReadModels.Account)
      {:ok, accounts} = Chronicle.ReadModels.get_instances(MyApp.ReadModels.Account, event_count: 500)

  ## Query the materialized container

      {:ok, result} = Chronicle.ReadModels.query(MyApp.ReadModels.Account, page: 1, page_size: 25)

      result.instances
      result.total_count

  ## Query metadata and history

      {:ok, snapshots} = Chronicle.ReadModels.snapshots(MyApp.ReadModels.Account, "account-1")
      {:ok, occurrences} = Chronicle.ReadModels.occurrences(MyApp.ReadModels.Account)
      {:ok, definitions} = Chronicle.ReadModels.definitions()
  """

  defmodule QueryResult do
    @moduledoc """
    Result returned by `Chronicle.ReadModels.query/2`.
    """

    @enforce_keys [:instances, :total_count, :page, :page_size]
    defstruct instances: [], total_count: 0, page: 1, page_size: 50

    @type t :: %__MODULE__{
            instances: [struct()],
            total_count: non_neg_integer(),
            page: pos_integer(),
            page_size: pos_integer()
          }
  end

  defmodule Snapshot do
    @moduledoc """
    Historical snapshot returned by `Chronicle.ReadModels.snapshots/3`.
    """

    @enforce_keys [:read_model, :events, :occurred, :correlation_id]
    defstruct read_model: nil, events: [], occurred: nil, correlation_id: nil

    @type t :: %__MODULE__{
            read_model: struct() | nil,
            events: [map()],
            occurred: DateTime.t() | String.t() | nil,
            correlation_id: term()
          }
  end

  defmodule Occurrence do
    @moduledoc """
    Metadata describing a replay occurrence for a read model.
    """

    @enforce_keys [
      :observer_id,
      :occurred,
      :identifier,
      :generation,
      :container_name,
      :revert_container_name
    ]
    defstruct observer_id: nil,
              occurred: nil,
              identifier: nil,
              generation: 1,
              container_name: nil,
              revert_container_name: nil

    @type t :: %__MODULE__{
            observer_id: String.t() | nil,
            occurred: DateTime.t() | String.t() | nil,
            identifier: String.t() | nil,
            generation: non_neg_integer(),
            container_name: String.t() | nil,
            revert_container_name: String.t() | nil
          }
  end

  defmodule Definition do
    @moduledoc """
    Read-model definition metadata returned by `Chronicle.ReadModels.definitions/1`.
    """

    @type observer_type :: :not_set | :reducer | :projection
    @type owner :: :none | :client | :server
    @type source :: :unknown | :code | :user

    @enforce_keys [
      :identifier,
      :generation,
      :container_name,
      :display_name,
      :schema,
      :indexes,
      :observer_type,
      :observer_identifier,
      :owner,
      :source,
      :sink
    ]
    defstruct identifier: nil,
              generation: 1,
              container_name: nil,
              display_name: nil,
              schema: nil,
              indexes: [],
              observer_type: :not_set,
              observer_identifier: nil,
              owner: :none,
              source: :unknown,
              sink: %{}

    @type t :: %__MODULE__{
            identifier: String.t() | nil,
            generation: non_neg_integer(),
            container_name: String.t() | nil,
            display_name: String.t() | nil,
            schema: String.t() | nil,
            indexes: [String.t()],
            observer_type: observer_type(),
            observer_identifier: String.t() | nil,
            owner: owner(),
            source: source(),
            sink: map()
          }
  end

  alias Cratis.Chronicle.Contracts.ReadModels.{
    GetAllInstancesRequest,
    GetDefinitionsRequest,
    GetInstanceByKeyRequest,
    GetInstancesRequest,
    GetOccurrencesRequest,
    GetSnapshotsByKeyRequest,
    ReadModelType,
    ReadModels
  }

  alias Cratis.Chronicle.Contracts.Compliance.{
    ReleaseRequest,
    Compliance
  }

  alias Chronicle.Connections.Connection
  alias Chronicle.ReadModels.Resilience
  alias Chronicle.Schemas.JsonSchemaGenerator

  @event_log_id "event-log"
  @unlimited_event_count 18_446_744_073_709_551_615
  @default_page 1
  @default_page_size 50

  @doc """
  Fetches a read model instance by key.

  This is the short alias for `get_instance_by_id/3`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence identifier (default: `"event-log"`)
    * `:session_id` — optional read-model session identifier

  Returns `{:ok, model_struct}` on success, or `{:ok, nil}` if no instance was found.
  """
  @spec get(module(), String.t(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  def get(model_module, key, opts \\ []), do: get_instance_by_id(model_module, key, opts)

  @doc """
  Fetches a read model instance by key.

  Mirrors the `getInstanceById()` naming used by the Chronicle C# and TypeScript
  clients while returning idiomatic Elixir tuples.
  """
  @spec get_instance_by_id(module(), String.t(), keyword()) ::
          {:ok, struct() | nil} | {:error, term()}
  def get_instance_by_id(model_module, key, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = read_model_id(model_module)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      session_id = Keyword.get(opts, :session_id, "")

      request =
        struct(GetInstanceByKeyRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          ReadModelIdentifier: model_id,
          EventSequenceId: event_sequence_id,
          ReadModelKey: key,
          SessionId: session_id
        )

      case call_resilient(config, fn -> ReadModels.Stub.get_instance_by_key(channel, request) end) do
        {:ok, response} ->
          case Map.get(response, :ReadModel, "") do
            "" ->
              {:ok, nil}

            nil ->
              {:ok, nil}

            "null" ->
              {:ok, nil}

            json ->
              instance = decode_model(model_module, json)

              if reducer_backed?(model_module, config) do
                {:ok, release_instance(instance, model_module, channel, config.event_store, namespace)}
              else
                {:ok, instance}
              end
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Replays and returns all instances for a read model.

  This is the short alias for `get_instances/2`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence identifier (default: `"event-log"`)
    * `:event_count` — maximum number of events to process (default: unlimited)
  """
  @spec all(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def all(model_module, opts \\ []), do: get_instances(model_module, opts)

  @doc """
  Replays and returns all instances for a read model.

  This matches the Chronicle `getInstances()` naming used in the C# and
  TypeScript clients.
  """
  @spec get_instances(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def get_instances(model_module, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = read_model_id(model_module)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_count = Keyword.get(opts, :event_count, @unlimited_event_count)

      request =
        struct(GetAllInstancesRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          ReadModelIdentifier: model_id,
          EventSequenceId: event_sequence_id,
          EventCount: event_count
        )

      case call_resilient(config, fn -> ReadModels.Stub.get_all_instances(channel, request) end) do
        {:ok, response} ->
          instances = decode_models(model_module, Map.get(response, :Instances, []))

          if reducer_backed?(model_module, config) do
            {:ok,
             Enum.map(instances, fn i ->
               release_instance(i, model_module, channel, config.event_store, namespace)
             end)}
          else
            {:ok, instances}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Queries the materialized read-model container directly.

  This complements the replay-oriented `all/2` and `get_instances/2` helpers.
  Use it when you need paging or want to inspect a specific replay occurrence.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:occurrence` — optional occurrence/container name for a replayed read model
    * `:page` — page number (default: `1`)
    * `:page_size` — page size (default: `50`)
  """
  @spec query(module(), keyword()) :: {:ok, QueryResult.t()} | {:error, term()}
  def query(model_module, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = read_model_id(model_module)
      occurrence = Keyword.get(opts, :occurrence, "")
      page = positive_integer_option(opts, :page, @default_page)
      page_size = positive_integer_option(opts, :page_size, @default_page_size)

      request =
        struct(GetInstancesRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          ReadModel: model_id,
          Occurrence: occurrence,
          Page: page,
          PageSize: page_size
        )

      case call_resilient(config, fn -> ReadModels.Stub.get_instances(channel, request) end) do
        {:ok, response} ->
          instances = decode_models(model_module, Map.get(response, :Instances, []))

          released =
            if reducer_backed?(model_module, config) do
              Enum.map(instances, fn i ->
                release_instance(i, model_module, channel, config.event_store, namespace)
              end)
            else
              instances
            end

          {:ok,
           %QueryResult{
             instances: released,
             total_count: Map.get(response, :TotalCount, 0),
             page: Map.get(response, :Page, page),
             page_size: Map.get(response, :PageSize, page_size)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns historical snapshots for a read model instance.

  Snapshots group the projected state together with the event batch that caused
  it, making this useful for troubleshooting projections and reducers.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence identifier (default: `"event-log"`)
  """
  @spec snapshots(module(), String.t(), keyword()) :: {:ok, [Snapshot.t()]} | {:error, term()}
  def snapshots(model_module, key, opts \\ []), do: get_snapshots_by_id(model_module, key, opts)

  @doc """
  Returns historical snapshots for a read model instance.

  This mirrors the `getSnapshotsById()` naming from the Chronicle C# and
  TypeScript clients.
  """
  @spec get_snapshots_by_id(module(), String.t(), keyword()) ::
          {:ok, [Snapshot.t()]} | {:error, term()}
  def get_snapshots_by_id(model_module, key, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = read_model_id(model_module)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(GetSnapshotsByKeyRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          ReadModelIdentifier: model_id,
          EventSequenceId: event_sequence_id,
          ReadModelKey: key
        )

      case call_resilient(config, fn -> ReadModels.Stub.get_snapshots_by_key(channel, request) end) do
        {:ok, response} ->
          snapshots =
            Map.get(response, :Snapshots, [])
            |> Enum.map(&decode_snapshot(model_module, &1))

          released_snapshots =
            if reducer_backed?(model_module, config) do
              Enum.map(snapshots, fn snapshot ->
                released_model =
                  release_instance(
                    snapshot.read_model,
                    model_module,
                    channel,
                    config.event_store,
                    namespace
                  )

                %{snapshot | read_model: released_model}
              end)
            else
              snapshots
            end

          {:ok, released_snapshots}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns replay occurrences for a read model.

  Occurrences represent replayed or rebuilt versions of a read model and are
  useful when inspecting rebuilds or alternative containers.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
  """
  @spec occurrences(module(), keyword()) :: {:ok, [Occurrence.t()]} | {:error, term()}
  def occurrences(model_module, opts \\ []), do: get_occurrences(model_module, opts)

  @doc """
  Returns replay occurrences for a read model.
  """
  @spec get_occurrences(module(), keyword()) :: {:ok, [Occurrence.t()]} | {:error, term()}
  def get_occurrences(model_module, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      model_id = read_model_id(model_module)

      request =
        struct(GetOccurrencesRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          Type: struct(ReadModelType, Identifier: model_id, Generation: 1)
        )

      case ReadModels.Stub.get_occurrences(channel, request) do
        {:ok, response} ->
          occurrences =
            Map.get(response, :Occurrences, [])
            |> Enum.map(&decode_occurrence/1)

          {:ok, occurrences}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns the registered read-model definitions for the current event store.

  This is useful for tooling, diagnostics, and documentation scenarios where you
  want to inspect the schema and owning observer for each read model.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
  """
  @spec definitions(keyword()) :: {:ok, [Definition.t()]} | {:error, term()}
  def definitions(opts \\ []), do: get_definitions(opts)

  @doc """
  Returns the registered read-model definitions for the current event store.
  """
  @spec get_definitions(keyword()) :: {:ok, [Definition.t()]} | {:error, term()}
  def get_definitions(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = struct(GetDefinitionsRequest, EventStore: config.event_store)

      case ReadModels.Stub.get_definitions(channel, request) do
        {:ok, response} ->
          definitions =
            Map.get(response, :ReadModels, [])
            |> Enum.map(&decode_definition/1)

          {:ok, definitions}

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

  # Runs a read-model retrieval with connection-aware resilience: it waits for the
  # connection to be registered and transparently retries the transient
  # "reducer is not connected" error the kernel returns during the brief
  # post-connect settle window.
  defp call_resilient(config, fun), do: Resilience.call(Map.get(config, :lifecycle), fun)

  defp read_model_id(model_module), do: model_module.__chronicle_read_model__(:id)

  defp decode_models(module, instances) do
    instances
    |> Enum.map(&decode_model(module, &1))
    |> Enum.reject(&is_nil/1)
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

  defp decode_snapshot(model_module, snapshot) do
    %Snapshot{
      read_model: decode_model(model_module, Map.get(snapshot, :ReadModel, "")),
      events: Map.get(snapshot, :Events, []),
      occurred: decode_timestamp(Map.get(snapshot, :Occurred)),
      correlation_id: Map.get(snapshot, :CorrelationId)
    }
  end

  defp decode_occurrence(occurrence) do
    type = Map.get(occurrence, :Type, %{})

    %Occurrence{
      observer_id: Map.get(occurrence, :ObserverId),
      occurred: decode_timestamp(Map.get(occurrence, :Occurred)),
      identifier: Map.get(type, :Identifier),
      generation: Map.get(type, :Generation, 1),
      container_name: Map.get(occurrence, :ContainerName),
      revert_container_name: Map.get(occurrence, :RevertContainerName)
    }
  end

  defp decode_definition(definition) when is_map(definition) do
    type = Map.get(definition, :Type, %{})

    %Definition{
      identifier: Map.get(type, :Identifier),
      generation: Map.get(type, :Generation, 1),
      container_name: Map.get(definition, :ContainerName),
      display_name: Map.get(definition, :DisplayName),
      schema: Map.get(definition, :Schema),
      indexes: Enum.map(Map.get(definition, :Indexes, []), &Map.get(&1, :PropertyPath)),
      observer_type: decode_observer_type(Map.get(definition, :ObserverType, 0)),
      observer_identifier: Map.get(definition, :ObserverIdentifier),
      owner: decode_owner(Map.get(definition, :Owner, 0)),
      source: decode_source(Map.get(definition, :Source, 0)),
      sink: Map.get(definition, :Sink, %{})
    }
  end

  defp decode_timestamp(nil), do: nil

  defp decode_timestamp(value) when is_map(value) do
    cond do
      Map.has_key?(value, :Value) -> decode_timestamp_value(Map.get(value, :Value))
      Map.has_key?(value, :value) -> decode_timestamp_value(Map.get(value, :value))
      true -> value
    end
  end

  defp decode_timestamp(value) when is_binary(value), do: decode_timestamp_value(value)
  defp decode_timestamp(value), do: value

  defp decode_timestamp_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, occurred, _offset} -> occurred
      _ -> value
    end
  end

  defp decode_timestamp_value(value), do: value

  defp decode_observer_type(0), do: :not_set
  defp decode_observer_type(1), do: :reducer
  defp decode_observer_type(2), do: :projection
  defp decode_observer_type(_), do: :not_set

  defp decode_owner(0), do: :none
  defp decode_owner(1), do: :client
  defp decode_owner(2), do: :server
  defp decode_owner(_), do: :none

  defp decode_source(0), do: :unknown
  defp decode_source(1), do: :code
  defp decode_source(2), do: :user
  defp decode_source(_), do: :unknown

  defp positive_integer_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"
    end
  end

  # Returns true when the given read model module is owned by a registered reducer.
  # Only reducer-backed read models require client-side compliance release — for
  # projection-backed models the server applies compliance rules before returning data.
  defp reducer_backed?(model_module, config) do
    config
    |> Map.get(:reducers, [])
    |> Enum.any?(fn reducer ->
      function_exported?(reducer, :__chronicle_reducer__, 1) and
        reducer.__chronicle_reducer__(:model) == model_module
    end)
  end

  # Returns true when the model module declares at least one PII field.
  defp has_pii?(model_module) do
    function_exported?(model_module, :__chronicle_pii__, 0) and
      not Enum.empty?(model_module.__chronicle_pii__())
  end

  # Resolves the data subject identifier from a read model instance.
  # Checks the explicit @chronicle_subject field first, then falls back to :id.
  # Returns nil when no usable subject value is found.
  defp resolve_subject(instance, model_module) do
    field =
      if function_exported?(model_module, :__chronicle_read_model__, 1) do
        model_module.__chronicle_read_model__(:subject) || :id
      else
        :id
      end

    case Map.get(instance, field) do
      nil -> nil
      "" -> nil
      value -> to_string(value)
    end
  end

  # Calls the Chronicle compliance Release endpoint to decrypt PII fields in a
  # single read model instance. Returns the original instance on any error.
  defp release_instance(nil, _model_module, _channel, _event_store, _namespace), do: nil

  defp release_instance(instance, model_module, channel, event_store, namespace) do
    if has_pii?(model_module) do
      case resolve_subject(instance, model_module) do
        nil ->
          instance

        subject ->
          schema = JsonSchemaGenerator.generate(model_module, key_transform: :identity)
          payload = instance |> Map.from_struct() |> Jason.encode!()

          request =
            struct(ReleaseRequest,
              EventStore: event_store,
              Namespace: namespace,
              Subject: subject,
              Schema: schema,
              Payload: payload
            )

          case Compliance.Stub.release(channel, request) do
            {:ok, response} ->
              if Map.get(response, :HasError, false) do
                instance
              else
                decode_model(model_module, Map.get(response, :Payload, "")) || instance
              end

            {:error, _} ->
              instance
          end
      end
    else
      instance
    end
  end
end
