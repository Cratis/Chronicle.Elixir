# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.InMemoryKernel do
  @moduledoc """
  An in-memory fake Chronicle kernel: a `GenServer` holding an event log plus a
  `%GRPC.Channel{}` interceptor answering the subset of the Chronicle wire protocol
  the client needs to append, read, and register artifacts.

  This is the seam `Chronicle.Testing.start_supervised_client/1` uses to run a real
  `Chronicle.Client` against no real kernel: the client's own append, constraint,
  and unit-of-work code runs completely unchanged, talking to this process instead
  of a socket.

  Supported RPCs: the compatibility check, `Append`/`AppendManyForEventSources`,
  reads (`ForEventSourceIdAndEventTypes`/`FromSequenceNumber`), `TailSequenceNumber`,
  `HasEventsForEventSourceId`, and the registration calls for event types, event
  sources, constraints, read models and projections (acknowledged, not modeled —
  constraint definitions are supplied directly at `start_link/1`, not parsed off the
  wire; see the moduledoc on `Chronicle.Testing`). Every other RPC returns
  `{:error, {:not_supported_in_memory, rpc}}` — most prominently
  `closes_stream` constraints and the actual `ReadModels`/`Projections` query
  surface, which is why `Chronicle.Testing.read_model/3` reads reducer state kept by
  `Chronicle.Testing.Dispatcher` instead of querying a kernel sink that does not exist.

  Concurrency scopes are honored along every dimension (`:event_source_id`,
  `:event_stream_type`, `:event_stream_id`, `:event_source_type`, `:event_types`,
  including `ExpectsNoMatchingEvent`). Constraints support `:unique` (ignoring
  casing, scoped, respecting removal) and `:unique_event_type`.
  """

  use GenServer

  alias Cratis.Chronicle.Contracts.Sequences, as: Wire

  alias Chronicle.Registration.Coordinator

  @unavailable_sequence_number 18_446_744_073_709_551_615

  @doc """
  Starts an in-memory kernel.

  ## Options

    * `:event_store` — default `"test"`
    * `:namespace` — default `"Default"`
    * `:event_types` — event type modules this kernel can decode (used for
      `Chronicle.Testing.appended_events/2` and assertions)
    * `:constraints` — resolved constraint definition maps, in the shape
      `Chronicle.Events.Constraints.from_event_types/1` /
      `from_constraint_modules/1` produce
    * `:name` — registered process name (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {start_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, start_opts)
  end

  @doc """
  Returns a `%GRPC.Channel{}` whose interceptor answers RPCs against this kernel.
  """
  @spec channel(GenServer.server()) :: GRPC.Channel.t()
  def channel(kernel) do
    %GRPC.Channel{
      host: "chronicle-testing",
      port: 0,
      adapter_payload: %{conn_pid: kernel},
      interceptors: [{__MODULE__.Interceptor, [kernel: kernel]}]
    }
  end

  @doc """
  Subscribes `pid` to every committed append batch:
  `{:chronicle_testing_appended, event_store, namespace, event_sequence_id, [wire_event, ...]}`.
  """
  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(kernel, pid), do: GenServer.call(kernel, {:subscribe, pid})

  @doc """
  Returns every committed wire event for `event_source_id`, across every event
  sequence, in append order.
  """
  @spec wire_events_for(GenServer.server(), String.t()) :: [map()]
  def wire_events_for(kernel, event_source_id),
    do: GenServer.call(kernel, {:wire_events_for, event_source_id})

  @doc """
  Returns every committed wire event, across every event source and sequence, in
  append order. Used by `Chronicle.Testing.Assertions`.
  """
  @spec all_wire_events(GenServer.server()) :: [map()]
  def all_wire_events(kernel), do: GenServer.call(kernel, :all_wire_events)

  @doc false
  @spec event_types(GenServer.server()) :: [module()]
  def event_types(kernel), do: GenServer.call(kernel, :event_types)

  @impl true
  def init(opts) do
    {:ok,
     %{
       event_store: Keyword.get(opts, :event_store, "test"),
       namespace: Keyword.get(opts, :namespace, "Default"),
       event_types: Keyword.get(opts, :event_types, []),
       constraints: normalize_constraints(Keyword.get(opts, :constraints, [])),
       sequences: %{},
       subscribers: []
     }}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: Enum.uniq([pid | state.subscribers])}}
  end

  def handle_call({:wire_events_for, event_source_id}, _from, state) do
    events =
      state.sequences
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&(&1.event_source_id == event_source_id))
      |> Enum.sort_by(& &1.sequence_number)
      |> Enum.map(& &1.wire)

    {:reply, events, state}
  end

  def handle_call(:all_wire_events, _from, state) do
    events =
      state.sequences
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(& &1.sequence_number)
      |> Enum.map(& &1.wire)

    {:reply, events, state}
  end

  def handle_call(:event_types, _from, state), do: {:reply, state.event_types, state}

  def handle_call({:append, es, ns, seq_id, request}, _from, state) do
    key = {es, ns, seq_id}
    existing = Map.get(state.sequences, key, [])

    event_type_id = get_field(request, :EventType, %{}) |> get_field(:Id, "")
    event_source_id = get_field(request, :EventSourceId, "")
    properties = decode_content(get_field(request, :Content, ""))

    with :ok <-
           check_constraints(
             state.constraints,
             existing,
             event_type_id,
             event_source_id,
             properties
           ),
         :ok <-
           check_concurrency(
             get_field(request, :ConcurrencyScope, nil),
             existing,
             event_source_id
           ) do
      sequence_number = length(existing)
      record = build_record(request, sequence_number, es, ns, seq_id, properties)
      state = put_record(state, key, record)
      notify(state, es, ns, seq_id, [record.wire])

      {:reply,
       {:ok, struct(Wire.AppendResponse, SequenceNumber: sequence_number, IsSuccess: true)},
       state}
    else
      {:error, response} -> {:reply, {:ok, response}, state}
    end
  end

  def handle_call({:append_many_for_event_sources, es, ns, seq_id, events, scopes}, _from, state) do
    key = {es, ns, seq_id}
    existing = Map.get(state.sequences, key, [])

    case check_and_build_records(state.constraints, existing, events, scopes, es, ns, seq_id) do
      {:ok, records} ->
        state = Enum.reduce(records, state, &put_record(&2, key, &1))
        wire_events = Enum.map(records, & &1.wire)
        notify(state, es, ns, seq_id, wire_events)

        {:reply,
         {:ok,
          struct(Wire.AppendManyResponse,
            IsSuccess: true,
            SequenceNumbers: Enum.map(records, & &1.sequence_number)
          )}, state}

      {:error, response} ->
        {:reply, {:ok, response}, state}
    end
  end

  def handle_call({:read_for_event_source, es, ns, seq_id, filters}, _from, state) do
    events =
      state.sequences
      |> Map.get({es, ns, seq_id}, [])
      |> Enum.filter(&matches_read_filters?(&1, filters))
      |> Enum.map(& &1.wire)

    {:reply, events, state}
  end

  def handle_call({:read_from_sequence_number, es, ns, seq_id, from, filters}, _from, state) do
    events =
      state.sequences
      |> Map.get({es, ns, seq_id}, [])
      |> Enum.filter(&(&1.sequence_number >= from))
      |> Enum.filter(&matches_read_filters?(&1, filters))
      |> Enum.map(& &1.wire)

    {:reply, events, state}
  end

  def handle_call({:tail_sequence_number, es, ns, seq_id, filters}, _from, state) do
    narrowed =
      state.sequences
      |> Map.get({es, ns, seq_id}, [])
      |> Enum.filter(&matches_read_filters?(&1, filters))

    sequence_number =
      case narrowed do
        [] -> @unavailable_sequence_number
        list -> list |> List.last() |> Map.fetch!(:sequence_number)
      end

    {:reply, sequence_number, state}
  end

  def handle_call({:has_events_for, es, ns, seq_id, event_source_id}, _from, state) do
    has_events? =
      state.sequences
      |> Map.get({es, ns, seq_id}, [])
      |> Enum.any?(&(&1.event_source_id == event_source_id))

    {:reply, has_events?, state}
  end

  defp put_record(state, key, record) do
    update_in(state, [:sequences, key], fn existing -> (existing || []) ++ [record] end)
  end

  defp notify(state, es, ns, seq_id, wire_events) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:chronicle_testing_appended, es, ns, seq_id, wire_events})
    end)
  end

  # Builds and validates every record in a batch atomically: a violation anywhere
  # in the batch rolls the whole append back (nothing is committed), mirroring the
  # kernel's own all-or-nothing AppendManyForEventSources semantics.
  defp check_and_build_records(constraints, existing, events, scopes, es, ns, seq_id) do
    events
    |> Enum.reduce_while({:ok, existing, []}, fn event, {:ok, virtual_existing, acc} ->
      event_type_id = get_field(event, :EventType, %{}) |> get_field(:Id, "")
      event_source_id = get_field(event, :EventSourceId, "")
      properties = decode_content(get_field(event, :Content, ""))
      scope = Map.get(scopes, event_source_id)

      with :ok <-
             check_constraints(
               constraints,
               virtual_existing,
               event_type_id,
               event_source_id,
               properties
             ),
           :ok <- check_concurrency(scope, virtual_existing, event_source_id) do
        sequence_number = length(virtual_existing)
        record = build_record(event, sequence_number, es, ns, seq_id, properties)
        {:cont, {:ok, virtual_existing ++ [record], acc ++ [record]}}
      else
        {:error, response} -> {:halt, {:error, response}}
      end
    end)
    |> case do
      {:ok, _virtual_existing, records} -> {:ok, records}
      {:error, response} -> {:error, response}
    end
  end

  defp get_field(nil, _key, default), do: default
  defp get_field(map, key, default) when is_map(map), do: Map.get(map, key, default)

  defp decode_content(content) when is_binary(content) and content != "" do
    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_content(_content), do: %{}

  defp matches_read_filters?(record, filters) do
    Enum.all?(filters, fn
      {:event_source_id, ""} -> true
      {:event_source_id, value} -> record.event_source_id == value
      {:event_source_type, ""} -> true
      {:event_source_type, value} -> record.event_source_type == value
      {:event_stream_type, ""} -> true
      {:event_stream_type, value} -> record.event_stream_type == value
      {:event_stream_id, ""} -> true
      {:event_stream_id, value} -> record.event_stream_id == value
      {:event_type_ids, []} -> true
      {:event_type_ids, ids} -> record.event_type_id in ids
    end)
  end

  defp build_record(request, sequence_number, es, ns, seq_id, properties) do
    event_source_id = get_field(request, :EventSourceId, "")
    event_source_type = get_field(request, :EventSourceType, "")
    event_stream_type = get_field(request, :EventStreamType, "")
    event_stream_id = get_field(request, :EventStreamId, "")
    event_type = get_field(request, :EventType, %{})
    event_type_id = get_field(event_type, :Id, "")
    generation = get_field(event_type, :Generation, 1)
    content = get_field(request, :Content, "")
    occurred = get_field(request, :Occurred, nil)

    wire = %{
      Context: %{
        EventType: %{Id: event_type_id, Generation: generation},
        EventSourceType: event_source_type,
        EventSourceId: event_source_id,
        SequenceNumber: sequence_number,
        EventStreamType: event_stream_type,
        EventStreamId: event_stream_id,
        Occurred: occurred,
        CorrelationId: "",
        Causation: [],
        CausedBy: nil,
        Tags: get_field(request, :Tags, []),
        Hash: "",
        ObservationState: 0,
        Subject: get_field(request, :Subject, ""),
        NamedTags: [],
        EventSource: get_field(request, :EventSource, nil),
        EventStore: es,
        Namespace: ns,
        EventSequenceId: seq_id
      },
      Content: content
    }

    %{
      sequence_number: sequence_number,
      event_source_id: event_source_id,
      event_source_type: event_source_type,
      event_stream_type: event_stream_type,
      event_stream_id: event_stream_id,
      event_type_id: event_type_id,
      properties: properties,
      wire: wire
    }
  end

  # --- Concurrency -----------------------------------------------------------

  defp check_concurrency(nil, _existing, _event_source_id), do: :ok

  defp check_concurrency(%{ExpectsNoMatchingEvent: true} = scope, existing, event_source_id) do
    case narrow(existing, scope, event_source_id) do
      [] -> :ok
      [match | _] -> {:error, concurrency_response(event_source_id, 0, match.sequence_number)}
    end
  end

  defp check_concurrency(scope, existing, event_source_id) do
    narrowed = narrow(existing, scope, event_source_id)

    actual =
      case narrowed do
        [] -> @unavailable_sequence_number
        list -> list |> List.last() |> Map.fetch!(:sequence_number)
      end

    expected = Map.get(scope, :SequenceNumber, @unavailable_sequence_number)

    if actual == expected do
      :ok
    else
      {:error, concurrency_response(event_source_id, expected, actual)}
    end
  end

  defp narrow(existing, scope, event_source_id) do
    stream_type = Map.get(scope, :EventStreamType)
    stream_id = Map.get(scope, :EventStreamId)
    source_type = Map.get(scope, :EventSourceType)
    event_types = Map.get(scope, :EventTypes)

    existing
    |> filter_if(Map.get(scope, :EventSourceId, false), &(&1.event_source_id == event_source_id))
    |> filter_if(nonempty?(stream_type), &(&1.event_stream_type == stream_type))
    |> filter_if(nonempty?(stream_id), &(&1.event_stream_id == stream_id))
    |> filter_if(nonempty?(source_type), &(&1.event_source_type == source_type))
    |> filter_if(nonempty?(event_types), fn record ->
      Enum.any?(event_types, &(Map.get(&1, :Id) == record.event_type_id))
    end)
  end

  defp nonempty?(nil), do: false
  defp nonempty?(""), do: false
  defp nonempty?([]), do: false
  defp nonempty?(_), do: true

  defp filter_if(list, false, _fun), do: list
  defp filter_if(list, true, fun), do: Enum.filter(list, fun)

  defp concurrency_response(event_source_id, expected, actual) do
    struct(Wire.AppendResponse,
      IsSuccess: false,
      HasConcurrencyViolations: true,
      ConcurrencyViolation:
        struct(Wire.ConcurrencyViolation,
          EventSourceId: event_source_id,
          ExpectedSequenceNumber: expected,
          ActualSequenceNumber: actual
        )
    )
  end

  # --- Constraints -------------------------------------------------------------

  defp check_constraints(constraints, existing, event_type_id, event_source_id, properties) do
    Enum.find_value(constraints, :ok, fn constraint ->
      case check_constraint(constraint, existing, event_type_id, event_source_id, properties) do
        :ok -> nil
        {:error, _} = error -> error
      end
    end)
  end

  defp check_constraint(
         %{type: :unique} = constraint,
         existing,
         event_type_id,
         event_source_id,
         properties
       ) do
    case Enum.find(constraint.event_definitions, &(&1.event_type_id == event_type_id)) do
      nil ->
        :ok

      %{on: on} ->
        values = property_values(properties, on, Map.get(constraint, :ignore_casing, false))
        claims = active_unique_claims(constraint, existing)

        case Map.get(claims, values) do
          nil -> :ok
          ^event_source_id -> :ok
          _other_source -> {:error, constraint_violation_response(constraint, event_type_id, on)}
        end
    end
  end

  defp check_constraint(
         %{type: :unique_event_type} = constraint,
         existing,
         event_type_id,
         event_source_id,
         _properties
       ) do
    if event_type_id in constraint.event_type_ids do
      claims = active_unique_event_type_claims(constraint, existing)

      if Map.has_key?(claims, event_source_id) do
        {:error, constraint_violation_response(constraint, event_type_id, [])}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_constraint(constraint, _existing, _event_type_id, _event_source_id, _properties) do
    raise ArgumentError,
          "Chronicle.Testing.InMemoryKernel does not recognize constraint shape #{inspect(constraint)}"
  end

  defp active_unique_claims(constraint, existing) do
    removed_with = constraint.removed_with_event_type_ids

    Enum.reduce(existing, %{}, fn record, claims ->
      cond do
        definition =
            Enum.find(constraint.event_definitions, &(&1.event_type_id == record.event_type_id)) ->
          values =
            property_values(
              record.properties,
              definition.on,
              Map.get(constraint, :ignore_casing, false)
            )

          Map.put(claims, values, record.event_source_id)

        record.event_type_id in removed_with ->
          claims
          |> Enum.reject(fn {_values, source} -> source == record.event_source_id end)
          |> Map.new()

        true ->
          claims
      end
    end)
  end

  defp active_unique_event_type_claims(constraint, existing) do
    removed_with = constraint.removed_with_event_type_ids

    Enum.reduce(existing, %{}, fn record, claims ->
      cond do
        record.event_type_id in constraint.event_type_ids ->
          Map.put(claims, record.event_source_id, true)

        record.event_type_id in removed_with ->
          Map.delete(claims, record.event_source_id)

        true ->
          claims
      end
    end)
  end

  defp property_values(properties, on, ignore_casing?) do
    Enum.map(on, fn field ->
      value = properties |> Map.get(Coordinator.camelize(to_string(field))) |> to_string()
      if ignore_casing?, do: String.downcase(value), else: value
    end)
  end

  defp constraint_violation_response(constraint, event_type_id, on) do
    details =
      case on do
        [] -> %{}
        properties -> %{"PropertyName" => Enum.join(properties, ",")}
      end

    struct(Wire.AppendResponse,
      IsSuccess: false,
      HasConstraintViolations: true,
      ConstraintViolations: [
        struct(Wire.ConstraintViolation,
          EventTypeId: event_type_id,
          ConstraintName: constraint.name,
          Message: resolve_message(constraint),
          Details: details
        )
      ]
    )
  end

  defp resolve_message(%{message: {module, function}}) when is_atom(module) and is_atom(function),
    do: ""

  defp resolve_message(%{message: message}) when is_binary(message), do: message
  defp resolve_message(_constraint), do: ""

  # --- Constraint normalization ------------------------------------------------

  # Resolves constraint definitions (as produced by Chronicle.Events.Constraints)
  # into a plain-data shape with event type ids only — no event type modules — so
  # constraint checking never has to resolve a module at check time. Constraints
  # this kernel does not model (closes_stream) are dropped; see the moduledoc.
  @doc false
  def normalize_constraints(definitions) do
    definitions
    |> Enum.filter(&(&1.type in [:unique, :unique_event_type]))
    |> Enum.map(&normalize_constraint/1)
  end

  defp normalize_constraint(%{type: :unique} = constraint) do
    %{
      type: :unique,
      name: constraint.name,
      ignore_casing: Map.get(constraint, :ignore_casing, false),
      message: Map.get(constraint, :message),
      event_definitions: Enum.map(constraint.event_definitions, &normalize_event_definition/1),
      removed_with_event_type_ids: resolve_ids(Map.get(constraint, :removed_with_event_types, []))
    }
  end

  defp normalize_constraint(%{type: :unique_event_type} = constraint) do
    %{
      type: :unique_event_type,
      name: constraint.name,
      message: Map.get(constraint, :message),
      event_type_ids: resolve_ids(Map.get(constraint, :event_type_ids, [])),
      removed_with_event_type_ids: resolve_ids(Map.get(constraint, :removed_with_event_types, []))
    }
  end

  defp normalize_event_definition(%{event_type: module, on: on}),
    do: %{event_type_id: module.__chronicle_event_type__(:id), on: on}

  defp normalize_event_definition(%{event_type_id: id, on: on}), do: %{event_type_id: id, on: on}

  defp resolve_ids(list) do
    Enum.map(list, fn
      id when is_binary(id) -> id
      module when is_atom(module) -> module.__chronicle_event_type__(:id)
    end)
  end

  defmodule Interceptor do
    @moduledoc false

    # The %GRPC.Channel{} interceptor: decodes the real wire request (round-tripped
    # through the generated codec, exactly like the real transport would), dispatches
    # it to the owning InMemoryKernel, and encodes a real wire response.

    alias Cratis.Chronicle.Contracts.Clients.{
      CompatibilityRequest,
      CompatibilityResponse,
      ConnectRequest,
      ConnectionKeepAlive
    }

    alias Cratis.Chronicle.Contracts.Sequences, as: Wire

    @ack_modules [
      Cratis.Chronicle.Contracts.EventStores.EnsureEventStoreRequest,
      Cratis.Chronicle.Contracts.Namespaces.EnsureNamespaceRequest,
      Cratis.Chronicle.Contracts.EventTypes.RegisterEventTypesRequest,
      Cratis.Chronicle.Contracts.EventSources.RegisterEventSourcesRequest,
      Cratis.Chronicle.Contracts.Events.Constraints.RegisterConstraintsRequest,
      Cratis.Chronicle.Contracts.ReadModels.RegisterManyRequest,
      Cratis.Chronicle.Contracts.Projections.RegisterRequest
    ]

    def call(stream, request, _next, opts) do
      kernel = Keyword.fetch!(opts, :kernel)
      decoded = request.__struct__.decode(request.__struct__.encode(request))
      respond(kernel, stream, decoded)
    end

    def respond(_kernel, _stream, %CompatibilityRequest{}) do
      roundtrip_ok(%CompatibilityResponse{
        IsCompatible: true,
        ServerVersion: "in-memory",
        ServerProtocolVersion: "in-memory"
      })
    end

    # Chronicle.Connections.Session dials this server-streaming RPC to establish a
    # session and starts a keepalive ping-pong on the reply stream (see
    # Chronicle.Connections.KeepAlive); the client's Lifecycle only flips to
    # :connected once the first keepalive arrives. A plain Enumerable answers it
    # here, fully bypassing the gRPC transport (see GRPC.Stub.call/5) -
    # it is never encoded/decoded.
    def respond(_kernel, _stream, %ConnectRequest{}) do
      {:ok, keepalive_stream()}
    end

    def respond(_kernel, _stream, %ConnectionKeepAlive{}) do
      {:ok, %Google.Protobuf.Empty{}}
    end

    def respond(_kernel, stream, %mod{} = _request) when mod in @ack_modules do
      roundtrip_ok(struct(stream.response_mod, IsAuthorized: true))
    end

    def respond(kernel, stream, %Wire.AppendRequest{} = request) do
      es = Map.get(request, :EventStore)
      ns = Map.get(request, :Namespace)
      seq_id = Map.get(request, :EventSequenceId)

      {:ok, response} = GenServer.call(kernel, {:append, es, ns, seq_id, request})
      roundtrip_ok(struct(stream.response_mod, IsAuthorized: true, Response: response))
    end

    def respond(kernel, stream, %Wire.AppendManyForEventSourcesRequest{} = request) do
      es = Map.get(request, :EventStore)
      ns = Map.get(request, :Namespace)
      seq_id = Map.get(request, :EventSequenceId)
      events = Map.get(request, :Events, [])

      scopes =
        Map.new(Map.get(request, :ConcurrencyScopes, []), fn entry ->
          {Map.get(entry, :EventSourceId), Map.get(entry, :Scope)}
        end)

      {:ok, response} =
        GenServer.call(kernel, {:append_many_for_event_sources, es, ns, seq_id, events, scopes})

      roundtrip_ok(struct(stream.response_mod, IsAuthorized: true, Response: response))
    end

    def respond(kernel, stream, %Wire.ForEventSourceIdAndEventTypesRequest{} = request) do
      filters = [
        event_source_id: Map.get(request, :EventSourceId, ""),
        event_source_type: Map.get(request, :EventSourceType, ""),
        event_stream_type: Map.get(request, :EventStreamType, ""),
        event_stream_id: Map.get(request, :EventStreamId, ""),
        event_type_ids: split_event_type_ids(Map.get(request, :EventTypeIds, ""))
      ]

      events =
        GenServer.call(
          kernel,
          {:read_for_event_source, Map.get(request, :EventStore), Map.get(request, :Namespace),
           Map.get(request, :EventSequenceId), filters}
        )

      roundtrip_ok(struct(stream.response_mod, IsAuthorized: true, Data: events))
    end

    def respond(kernel, stream, %Wire.FromSequenceNumberRequest{} = request) do
      filters = [
        event_source_id: Map.get(request, :EventSourceId, ""),
        event_source_type: "",
        event_stream_type: "",
        event_stream_id: "",
        event_type_ids: split_event_type_ids(Map.get(request, :EventTypeIds, ""))
      ]

      events =
        GenServer.call(
          kernel,
          {:read_from_sequence_number, Map.get(request, :EventStore),
           Map.get(request, :Namespace), Map.get(request, :EventSequenceId),
           Map.get(request, :FromEventSequenceNumber, 0), filters}
        )

      roundtrip_ok(struct(stream.response_mod, IsAuthorized: true, Data: events))
    end

    def respond(kernel, stream, %Wire.TailSequenceNumberRequest{} = request) do
      filters = [
        event_source_id: Map.get(request, :EventSourceId, ""),
        event_source_type: Map.get(request, :EventSourceType, ""),
        event_stream_type: Map.get(request, :EventStreamType, ""),
        event_stream_id: Map.get(request, :EventStreamId, ""),
        event_type_ids: split_event_type_ids(Map.get(request, :EventTypeIds, ""))
      ]

      sequence_number =
        GenServer.call(
          kernel,
          {:tail_sequence_number, Map.get(request, :EventStore), Map.get(request, :Namespace),
           Map.get(request, :EventSequenceId), filters}
        )

      roundtrip_ok(
        struct(stream.response_mod,
          IsAuthorized: true,
          Data: struct(Wire.EventSequenceTailResponse, SequenceNumber: sequence_number)
        )
      )
    end

    def respond(kernel, stream, %Wire.HasEventsForEventSourceIdRequest{} = request) do
      has_events? =
        GenServer.call(
          kernel,
          {:has_events_for, Map.get(request, :EventStore), Map.get(request, :Namespace),
           Map.get(request, :EventSequenceId), Map.get(request, :EventSourceId)}
        )

      roundtrip_ok(
        struct(stream.response_mod,
          IsAuthorized: true,
          Data: struct(Wire.EventSourceEventsResponse, HasEvents: has_events?)
        )
      )
    end

    def respond(_kernel, _stream, request) do
      {:error, {:not_supported_in_memory, request.__struct__}}
    end

    defp split_event_type_ids(""), do: []
    defp split_event_type_ids(nil), do: []
    defp split_event_type_ids(ids), do: String.split(ids, ",", trim: true)

    defp roundtrip_ok(response),
      do: {:ok, response.__struct__.decode(response.__struct__.encode(response))}

    defp keepalive_stream do
      Stream.resource(
        fn -> :first end,
        fn
          :first -> {[{:ok, %ConnectionKeepAlive{}}], :rest}
          :rest -> receive_keepalive_tick()
        end,
        fn _ -> :ok end
      )
    end

    defp receive_keepalive_tick do
      receive do
      after
        1_000 -> {[{:ok, %ConnectionKeepAlive{}}], :rest}
      end
    end
  end
end
