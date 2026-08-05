# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EventLog do
  @moduledoc """
  Appends and queries events in a Chronicle event log.

  The event log is the primary `EventSequence` in Chronicle. Use `append/3` to
  record domain events for a given event source (such as an aggregate root).

  ## Usage

      :ok = Chronicle.EventSequences.EventLog.append("account-1", %MyApp.Events.AccountOpened{
        account_id: "account-1",
        owner_name: "Alice",
        initial_balance: 500
      })

  To append to a specific client:

      :ok = Chronicle.EventSequences.EventLog.append("account-1", event, client: :my_chronicle)

  ## Multiple events

      events = [
        %MyApp.Events.AccountOpened{account_id: "1", owner_name: "Alice"},
        %MyApp.Events.FundsDeposited{account_id: "1", amount: 500}
      ]
      :ok = Chronicle.EventSequences.EventLog.append_many("account-1", events)

  ## Transactions

  When a `Chronicle.Transactions.UnitOfWork` is active, append operations are
  buffered locally and only sent to Chronicle when the unit of work is committed.
  """

  alias Cratis.Chronicle.Contracts.EventSequences.{
    AppendManyRequest,
    AppendRequest,
    Causation,
    CompleteStreamRequest,
    EventSequences,
    EventToAppend,
    EventType,
    GetForEventSourceIdAndEventTypesRequest,
    GetFromEventSequenceNumberRequest,
    GetTailSequenceNumberRequest,
    HasEventsForEventSourceIdRequest,
    Identity,
    RedactForEventSourceRequest,
    RedactRequest,
    SerializableDateTimeOffset
  }

  alias Cratis.Chronicle.Contracts.EventSequences.ConcurrencyScope, as: ContractConcurrencyScope

  alias Chronicle.Auditing.{CausationEntry, CausationManager, CausationType}
  alias Chronicle.Correlation.{CorrelationId, CorrelationIdManager}
  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Identity.IdentityProvider

  alias Chronicle.Events.ConcurrencyScope, as: ClientConcurrencyScope

  alias Chronicle.Connections.Connection
  alias Chronicle.Transactions.UnitOfWork

  alias Bcl.Guid, as: BclGuid

  @event_log_id "event-log"
  @unavailable_sequence_number 18_446_744_073_709_551_615

  @doc """
  Appends a single event to the event log for the given event source.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_source_type` — the event source type (default: `"Default"`)
    * `:event_stream_type` — the event stream type (default: `"All"`)
    * `:event_stream_id` — the event stream ID (default: `"Default"`)
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
    * `:correlation_id` — correlation id override (`Chronicle.Correlation.CorrelationId` or string)
    * `:identity` — identity override (`Chronicle.Identity`)
    * `:causation` — causation chain override (list of `Chronicle.Auditing.CausationEntry`)
    * `:concurrency_scope` — `Chronicle.Events.ConcurrencyScope` or keyword options with
      `:sequence_number`, `:event_source_id`, `:event_stream_type`, `:event_stream_id`,
      `:event_source_type`, and `:event_types`

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  def append(event_source_id, event, opts \\ []) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    if UnitOfWork.has_current?() do
      buffer_append(event_sequence_id, event_source_id, event, opts)
    else
      do_append(event_sequence_id, event_source_id, event, opts)
    end
  end

  @doc """
  Appends multiple events to the event log for the given event source.

  All events are appended atomically. Each event must be a struct that
  `use Chronicle.Events.EventType`.

  ## Options

  Same as `append/3`, including `:event_sequence_id` and `:concurrency_scope`.
  """
  @spec append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  def append_many(event_source_id, events, opts \\ [])

  def append_many(_event_source_id, [], _opts), do: :ok

  def append_many(event_source_id, events, opts) when is_list(events) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    if UnitOfWork.has_current?() do
      Enum.each(events, fn event ->
        buffer_append(event_sequence_id, event_source_id, event, opts)
      end)

      :ok
    else
      do_append_many(event_sequence_id, event_source_id, events, opts)
    end
  end

  @doc false
  @spec buffer_append(String.t(), String.t(), struct(), keyword()) :: :ok
  def buffer_append(event_sequence_id, event_source_id, event, opts \\ []) do
    buffered_event = build_event_for_event_source_id(event_source_id, event, opts, :transactional)

    UnitOfWork.add_event(
      UnitOfWork.current(),
      event_sequence_id,
      buffered_event,
      client: Keyword.get(opts, :client, Chronicle.Client),
      namespace: Keyword.get(opts, :namespace)
    )
  end

  @doc false
  @spec commit_transaction(map()) :: {:ok, map()} | {:error, term()}
  def commit_transaction(%{events: []}) do
    {:ok, UnitOfWork.default_commit_result([], [], [])}
  end

  def commit_transaction(%{event_sequence_id: event_sequence_id, events: events} = state) do
    client = Map.get(state, :client, Chronicle.Client)

    with {:ok, channel, config} <- resolve_channel_for_client(client) do
      namespace = Map.get(state, :namespace) || config.namespace
      correlation_id = Map.fetch!(state, :correlation_id)

      request =
        build_append_many_request(config, namespace, event_sequence_id, events,
          correlation_id: correlation_id,
          causation: batch_causation(events),
          identity: batch_identity(events)
        )

      case EventSequences.Stub.append_many(channel, request) do
        {:ok, response} ->
          {:ok,
           UnitOfWork.default_commit_result(
             get_sequence_numbers(response),
             get_constraint_violations(response),
             get_append_errors(response)
           )}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns events for the given event source ID from the event log.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_types` — list of event type modules to filter by (default: all)
    * `:event_source_type` — the event source type to filter by (default: all)
    * `:event_stream_type` — the event stream type to filter by (default: all)
    * `:event_stream_id` — the event stream id to filter by (default: all)

  Returns `{:ok, [appended_event]}` or `{:error, reason}`.
  """
  @spec get_for_event_source(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_for_event_source(event_source_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])

      event_types = Enum.map(event_type_modules, &build_event_type_for_module/1)

      request =
        struct(GetForEventSourceIdAndEventTypesRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventSourceId: event_source_id,
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, ""),
          EventTypes: event_types
        )

      case EventSequences.Stub.get_for_event_source_id_and_event_types(channel, request) do
        {:ok, response} -> {:ok, Map.get(response, :Events, [])}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns events from (and including) the given sequence number onward.

  Mirrors the Chronicle C# and TypeScript clients' `GetFromSequenceNumber()`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_source_id` — optional event source id to filter by (default: all)
    * `:event_types` — list of event type modules to filter by (default: all)

  Returns `{:ok, [appended_event]}` or `{:error, reason}`.
  """
  @spec get_from_sequence_number(non_neg_integer(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_from_sequence_number(sequence_number, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])
      event_types = Enum.map(event_type_modules, &build_event_type_for_module/1)

      request =
        struct(GetFromEventSequenceNumberRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          FromEventSequenceNumber: sequence_number,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventTypes: event_types
        )

      case EventSequences.Stub.get_events_from_event_sequence_number(channel, request) do
        {:ok, response} -> {:ok, Map.get(response, :Events, [])}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns the tail sequence number for an event sequence.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_source_type` — the event source type to filter by (default: `"Default"`)
    * `:event_stream_type` — the event stream type to filter by (default: `"Default"`)
    * `:event_stream_id` — the event stream id to filter by (default: all)
    * `:event_types` — list of event type modules to filter by (default: all)
  """
  @spec get_tail_sequence_number(String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_tail_sequence_number(event_source_id \\ nil, opts \\ []) do
    case raw_tail_sequence_number(event_source_id, opts) do
      {:ok, sequence_number} -> {:ok, normalize_sequence_number(sequence_number)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the sequence number that will be assigned to the next appended event.

  Mirrors the Chronicle C# and TypeScript clients' `GetNextSequenceNumber()`.

  ## Options

  Same as `get_tail_sequence_number/2`.
  """
  @spec get_next_sequence_number(String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_next_sequence_number(event_source_id \\ nil, opts \\ []) do
    case raw_tail_sequence_number(event_source_id, opts) do
      {:ok, @unavailable_sequence_number} -> {:ok, 0}
      {:ok, sequence_number} -> {:ok, sequence_number + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the tail sequence number scoped to only the event types that the
  given reactor or reducer module subscribes to (its `@handles` declarations).

  Mirrors the Chronicle C# client's `GetTailSequenceNumberForObserver()`.

  ## Options

  Same as `get_tail_sequence_number/2`, minus `:event_types` (derived from
  `observer_module`).
  """
  @spec get_tail_sequence_number_for_observer(module(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_tail_sequence_number_for_observer(observer_module, opts \\ []) do
    event_types = observer_event_types(observer_module)
    get_tail_sequence_number(nil, Keyword.put(opts, :event_types, event_types))
  end

  @doc """
  Completes a named, non-default stream so that no further events can be
  appended to it.

  The default stream (event stream type `"All"` paired with the default event
  stream id) can never be completed. Completing an already-completed stream
  leaves it in its completed state.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)

  Returns `{:ok, tail_sequence_number}` on success, or
  `{:error, :default_stream_cannot_be_completed | :already_completed}`.
  """
  @spec complete_stream(String.t(), String.t(), keyword()) ::
          {:ok, non_neg_integer()}
          | {:error, :default_stream_cannot_be_completed | :already_completed | term()}
  def complete_stream(event_stream_type, event_stream_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(CompleteStreamRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventStreamType: event_stream_type,
          EventStreamId: event_stream_id
        )

      case EventSequences.Stub.complete_stream(channel, request) do
        {:ok, response} ->
          if Map.get(response, :IsSuccess, false) do
            {:ok, normalize_sequence_number(Map.get(response, :SequenceNumber, 0))}
          else
            {:error, decode_complete_stream_error(Map.get(response, :Error))}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Redacts a single event at a specific sequence number, permanently replacing
  its content for compliance/GDPR erasure. This is destructive and irreversible.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
  """
  @spec redact(non_neg_integer(), String.t(), keyword()) :: :ok | {:error, term()}
  def redact(sequence_number, reason, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(RedactRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          SequenceNumber: sequence_number,
          Reason: reason,
          CorrelationId: build_correlation_id(opts),
          Causation: causation_entries_to_proto(build_causation_entries(opts, :plain)),
          CausedBy: identity_to_proto(build_identity(opts))
        )

      case EventSequences.Stub.redact(channel, request) do
        {:ok, _response} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Redacts all events for a given event source, optionally filtered to
  specific event types. Permanently replaces content for compliance/GDPR
  erasure. This is destructive and irreversible.

  ## Options

  Same as `redact/3`.
  """
  @spec redact_for_event_source(String.t(), String.t(), [module()], keyword()) ::
          :ok | {:error, term()}
  def redact_for_event_source(event_source_id, reason, event_types \\ [], opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      wire_event_types = Enum.map(event_types, &build_event_type_for_module/1)

      request =
        struct(RedactForEventSourceRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceId: event_source_id,
          Reason: reason,
          EventTypes: wire_event_types,
          CorrelationId: build_correlation_id(opts),
          Causation: causation_entries_to_proto(build_causation_entries(opts, :plain)),
          CausedBy: identity_to_proto(build_identity(opts))
        )

      case EventSequences.Stub.redact_for_event_source(channel, request) do
        {:ok, _response} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Checks whether an event sequence has events for an event source id.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
  """
  @spec has_events_for?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def has_events_for?(event_source_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(HasEventsForEventSourceIdRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceId: event_source_id
        )

      case EventSequences.Stub.has_events_for_event_source_id(channel, request) do
        {:ok, response} ->
          has_events = Map.get(response, :HasEvents, Map.get(response, :has_events, false))
          {:ok, has_events}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_append(event_sequence_id, event_source_id, event, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_to_append = build_event_for_event_source_id(event_source_id, event, opts, :append)

      request =
        struct(AppendRequest,
          CorrelationId: build_correlation_id(opts),
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceType: event_to_append.event_source_type,
          EventSourceId: event_to_append.event_source_id,
          EventStreamType: event_to_append.event_stream_type,
          EventStreamId: event_to_append.event_stream_id,
          EventType: build_event_type(event_to_append.event),
          Content: encode_event(event_to_append.event),
          Causation: causation_entries_to_proto(event_to_append.causation),
          CausedBy: identity_to_proto(event_to_append.identity),
          ConcurrencyScope: build_concurrency_scope(event_to_append.concurrency_scope),
          Occurred: datetime_offset_for(event_to_append.occurred),
          Tags: event_to_append.tags || [],
          Subject: event_to_append.subject || ""
        )

      case EventSequences.Stub.append(channel, request) do
        {:ok, response} -> normalize_response(response)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_append_many(event_sequence_id, event_source_id, events, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      events_to_append =
        Enum.map(events, fn event ->
          build_event_for_event_source_id(event_source_id, event, opts, :append_many)
        end)

      request =
        build_append_many_request(config, namespace, event_sequence_id, events_to_append, opts)

      case EventSequences.Stub.append_many(channel, request) do
        {:ok, response} -> normalize_response(response)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_append_many_request(config, namespace, event_sequence_id, events, opts) do
    request =
      struct(AppendManyRequest,
        EventStore: config.event_store,
        Namespace: namespace,
        EventSequenceId: event_sequence_id,
        Events: Enum.map(events, &event_to_proto/1)
      )

    request
    |> maybe_put(:CorrelationId, build_correlation_id(opts))
    |> maybe_put(
      :Causation,
      causation_entries_to_proto(
        Keyword.get(opts, :causation, build_causation_entries(opts, :append_many))
      )
    )
    |> maybe_put_identity(
      batch_identity(events) || Keyword.get(opts, :identity) || build_identity(opts)
    )
    |> maybe_put(:ConcurrencyScopes, build_concurrency_scopes(events))
  end

  defp build_event_for_event_source_id(event_source_id, event, opts, mode) do
    %EventForEventSourceId{
      event_source_id: event_source_id,
      event: event,
      event_source_type: Keyword.get(opts, :event_source_type, "Default"),
      event_stream_type: Keyword.get(opts, :event_stream_type, "All"),
      event_stream_id: Keyword.get(opts, :event_stream_id, "Default"),
      tags: Keyword.get(opts, :tags, []),
      subject: Keyword.get(opts, :subject, ""),
      occurred: Keyword.get(opts, :occurred, DateTime.utc_now()),
      concurrency_scope: Keyword.get(opts, :concurrency_scope),
      causation: build_causation_entries(opts, mode),
      identity: build_identity(opts)
    }
  end

  defp event_to_proto(%EventForEventSourceId{} = event_to_append) do
    event =
      struct(EventToAppend,
        EventSourceType: event_to_append.event_source_type,
        EventSourceId: event_to_append.event_source_id,
        EventStreamType: event_to_append.event_stream_type,
        EventStreamId: event_to_append.event_stream_id,
        EventType: build_event_type(event_to_append.event),
        Content: encode_event(event_to_append.event),
        Tags: event_to_append.tags || []
      )

    event
    |> maybe_put(:Causation, causation_entries_to_proto(event_to_append.causation))
    |> maybe_put_identity(event_to_append.identity)
    |> maybe_put(:ConcurrencyScope, build_concurrency_scope(event_to_append.concurrency_scope))
    |> maybe_put(:Occurred, datetime_offset_for(event_to_append.occurred))
    |> maybe_put(:Subject, event_to_append.subject || "")
  end

  defp build_event_type(event) do
    module = event.__struct__
    build_event_type_for_module(module)
  end

  defp build_event_type_for_module(module) do
    struct(EventType,
      Id: module.__chronicle_event_type__(:id),
      Generation: module.__chronicle_event_type__(:generation)
    )
  end

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    resolve_channel_for_client(client)
  end

  defp resolve_channel_for_client(client) do
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

  defp encode_event(event) do
    event
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {snake_to_camel(Atom.to_string(key)), value} end)
    |> Map.new()
    |> Jason.encode!()
  end

  defp snake_to_camel(snake) do
    [head | tail] = String.split(snake, "_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end

  defp build_correlation_id(opts) do
    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        %CorrelationId{} = id -> id
        id when is_binary(id) -> CorrelationId.new(id)
        _ -> CorrelationIdManager.current()
      end

    guid = struct(BclGuid)

    cond do
      Map.has_key?(guid, :Value) -> Map.put(guid, :Value, correlation_id.value)
      Map.has_key?(guid, :value) -> Map.put(guid, :value, correlation_id.value)
      true -> guid
    end
  end

  defp build_identity(opts) do
    Keyword.get(opts, :identity, IdentityProvider.get_current())
  end

  defp identity_to_proto(nil), do: nil

  defp identity_to_proto(identity) do
    proto =
      struct(Identity,
        Subject: identity.subject,
        Name: identity.name,
        UserName: identity.user_name
      )

    cond do
      Map.has_key?(proto, :OnBehalfOf) and not is_nil(identity.on_behalf_of) ->
        Map.put(proto, :OnBehalfOf, identity_to_proto(identity.on_behalf_of))

      Map.has_key?(proto, :on_behalf_of) and not is_nil(identity.on_behalf_of) ->
        Map.put(proto, :on_behalf_of, identity_to_proto(identity.on_behalf_of))

      true ->
        proto
    end
  end

  defp build_causation_entries(opts, :transactional) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    base_entries =
      case Keyword.get(opts, :causation) do
        entries when is_list(entries) and entries != [] -> entries
        _ -> CausationManager.get_current_chain()
      end

    base_entries ++
      [
        CausationEntry.new(CausationType.transactional_event_sequence(), %{
          eventSequenceId: event_sequence_id
        })
      ]
  end

  defp build_causation_entries(opts, :plain) do
    case Keyword.get(opts, :causation) do
      entries when is_list(entries) and entries != [] -> entries
      _ -> CausationManager.get_current_chain()
    end
  end

  defp build_causation_entries(opts, mode) do
    entries =
      case Keyword.get(opts, :causation) do
        entries when is_list(entries) and entries != [] -> entries
        _ -> CausationManager.get_current_chain()
      end

    entries ++ [client_causation_for_mode(mode)]
  end

  defp client_causation_for_mode(:append), do: CausationEntry.new(CausationType.append_event())

  defp client_causation_for_mode(:append_many),
    do: CausationEntry.new(CausationType.append_many_events())

  defp causation_entries_to_proto(entries) when is_list(entries) do
    Enum.map(entries, &causation_to_proto/1)
  end

  defp causation_to_proto(%CausationEntry{} = entry) do
    struct(Causation,
      Type: entry.type.value,
      Occurred: datetime_offset_for(entry.occurred)
    )
    |> maybe_put(:Properties, entry.properties)
  end

  defp causation_to_proto(entry) when is_map(entry) do
    type =
      case Map.get(entry, :type) do
        %CausationType{value: value} -> value
        value when is_binary(value) -> value
        value when is_atom(value) -> Atom.to_string(value)
        _ -> "Unknown"
      end

    properties =
      Map.get(entry, :properties, %{})
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
      |> Map.new()

    struct(Causation,
      Type: type,
      Occurred: current_datetime_offset()
    )
    |> maybe_put(:Properties, properties)
  end

  defp build_concurrency_scope(scope_or_opts) do
    scope = ClientConcurrencyScope.normalize(scope_or_opts)

    struct(ContractConcurrencyScope)
    |> maybe_put(:SequenceNumber, scope.sequence_number)
    |> maybe_put(:EventSourceId, scope.event_source_id)
    |> maybe_put(:EventStreamType, scope.event_stream_type)
    |> maybe_put(:EventStreamId, scope.event_stream_id)
    |> maybe_put(:EventSourceType, scope.event_source_type)
    |> maybe_put(:EventTypes, Enum.map(scope.event_types, &build_event_type_for_module/1))
  end

  defp current_datetime_offset do
    datetime_offset_for(DateTime.utc_now())
  end

  defp datetime_offset_for(nil), do: current_datetime_offset()

  defp datetime_offset_for(%DateTime{} = occurred) do
    struct(SerializableDateTimeOffset, Value: DateTime.to_iso8601(occurred))
  end

  defp maybe_put(nil, _key, _value), do: nil
  defp maybe_put(struct, _key, nil), do: struct

  defp maybe_put(struct, key, value) do
    snake_case_key = key |> Atom.to_string() |> Macro.underscore() |> String.to_atom()

    cond do
      Map.has_key?(struct, key) -> Map.put(struct, key, value)
      Map.has_key?(struct, snake_case_key) -> Map.put(struct, snake_case_key, value)
      true -> struct
    end
  end

  defp maybe_put_identity(struct, identity) do
    maybe_put(struct, :CausedBy, identity_to_proto(identity))
  end

  defp build_concurrency_scopes(events) do
    events
    |> Enum.reduce(%{}, fn %EventForEventSourceId{} = event, scopes ->
      case event.concurrency_scope do
        nil -> scopes
        scope -> Map.put_new(scopes, event.event_source_id, build_concurrency_scope(scope))
      end
    end)
    |> case do
      scopes when map_size(scopes) == 0 -> nil
      scopes -> scopes
    end
  end

  defp batch_causation([%EventForEventSourceId{causation: causation} | _]), do: causation
  defp batch_causation(_events), do: []

  defp batch_identity(events) do
    events
    |> Enum.find_value(fn
      %EventForEventSourceId{identity: nil} -> nil
      %EventForEventSourceId{identity: identity} -> identity
    end)
  end

  defp normalize_response(response) do
    violations = get_constraint_violations(response)
    errors = get_append_errors(response)

    cond do
      violations != [] -> {:error, {:constraint_violations, violations}}
      errors != [] -> {:error, {:append_errors, errors}}
      true -> :ok
    end
  end

  defp get_sequence_numbers(response) do
    response
    |> Map.get(:SequenceNumbers, Map.get(response, :sequence_numbers, []))
    |> Enum.map(&normalize_sequence_number/1)
  end

  defp get_constraint_violations(response) do
    Map.get(response, :ConstraintViolations, Map.get(response, :constraint_violations, []))
  end

  defp get_append_errors(response) do
    Map.get(response, :Errors, Map.get(response, :errors, []))
  end

  defp normalize_sequence_number(@unavailable_sequence_number), do: 0
  defp normalize_sequence_number(value) when is_integer(value) and value >= 0, do: value
  defp normalize_sequence_number(_), do: 0

  # Fetches the tail sequence number without collapsing the "unavailable" sentinel,
  # so callers that need to distinguish "no tail" from "tail at 0" (like
  # get_next_sequence_number/2) can do so.
  defp raw_tail_sequence_number(event_source_id, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])
      event_types = Enum.map(event_type_modules, &build_event_type_for_module/1)

      request =
        struct(GetTailSequenceNumberRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceId: event_source_id || "",
          EventTypes: event_types,
          EventSourceType: Keyword.get(opts, :event_source_type, "Default"),
          EventStreamId: Keyword.get(opts, :event_stream_id, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, "Default")
        )

      case EventSequences.Stub.get_tail_sequence_number(channel, request) do
        {:ok, response} ->
          {:ok, Map.get(response, :SequenceNumber, Map.get(response, :sequence_number, 0))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Returns the event type modules a reactor or reducer module subscribes to,
  # via its `@handles` declarations.
  defp observer_event_types(module) do
    cond do
      function_exported?(module, :__chronicle_reactor__, 1) -> module.__chronicle_reactor__(:handles)
      function_exported?(module, :__chronicle_reducer__, 1) -> module.__chronicle_reducer__(:handles)
      true -> []
    end
  end

  defp decode_complete_stream_error(:DefaultStreamCannotBeCompleted),
    do: :default_stream_cannot_be_completed

  defp decode_complete_stream_error(_), do: :already_completed
end
