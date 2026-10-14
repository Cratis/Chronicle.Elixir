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

  alias Cratis.Chronicle.Contracts.Sequences.{
    AppendManyForEventSourcesRequest,
    AppendRequest,
    Causation,
    CompleteStreamRequest,
    EventSequences,
    EventSourceConcurrencyScope,
    EventType,
    ForEventSourceIdAndEventTypesRequest,
    FromSequenceNumberRequest,
    HasEventsForEventSourceIdRequest,
    Identity,
    RedactForEventSourceRequest,
    RedactRequest,
    SerializableDateTimeOffset,
    TailSequenceNumberRequest
  }

  alias Cratis.Chronicle.Contracts.Sequences.ConcurrencyScope, as: ContractConcurrencyScope
  alias Cratis.Chronicle.Contracts.Sequences.EventForEventSourceId, as: WireEventForEventSourceId

  alias Cratis.Chronicle.Contracts.Observation.Observers
  alias Cratis.Chronicle.Contracts.Observation.WaitForObserverCompletionRequest

  alias Chronicle.Auditing.{CausationEntry, CausationManager, CausationType}
  alias Chronicle.Correlation.{CorrelationId, CorrelationIdManager}
  alias Chronicle.Diagnostics.Tracing
  alias Chronicle.EventSequences.{ConcurrencyStrategy, DefinitionRouting, EventForEventSourceId}
  alias Chronicle.Identity.IdentityProvider
  alias Chronicle.WireResult

  alias Chronicle.Events.ConcurrencyScope, as: ClientConcurrencyScope

  alias Chronicle.Connections.Connection
  alias Chronicle.EventSequences.{AppendResponse, AppendResult, PreparedEvent}
  alias Chronicle.Events.EventType, as: ClientEventType
  alias Chronicle.Transactions.UnitOfWork

  alias Bcl.Guid, as: BclGuid

  @event_log_id "event-log"
  @unavailable_sequence_number 18_446_744_073_709_551_615
  @default_wait_for_completion_timeout 5_000

  @doc """
  Appends a single event to the event log for the given event source.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_source_type` — explicit event source type, otherwise resolved by the kernel
    * `:event_stream_type` — explicit event stream type, otherwise resolved by the kernel
    * `:event_stream_id` — explicit event stream ID, otherwise resolved by the kernel
    * `:occurred` — explicit `DateTime`; omission leaves the timestamp to the kernel
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
    * `:correlation_id` — correlation id override (`Chronicle.Correlation.CorrelationId` or string)
    * `:identity` — identity override (`Chronicle.Identity`)
    * `:causation` — causation chain override (list of `Chronicle.Auditing.CausationEntry`)
    * `:concurrency_scope` — `Chronicle.Events.ConcurrencyScope` or keyword options with
      `:sequence_number`, `:event_source_id`, `:event_stream_type`, `:event_stream_id`,
      `:event_source_type`, and `:event_types`

    * `:event_source` — a `Chronicle.EventSources.EventSource` module (or its name) the
      append goes through. Its name becomes the event source type and `EventSource`
      metadata of the event, and its concurrency dimensions apply when no explicit
      `:concurrency_scope` is given
    * `:event_stream` — the name of a stream declared by `:event_source`; written as the
      event stream type. Unknown sources/streams and contradicting
      `:event_source_type`/`:event_stream_type` values return
      `{:error, {:unknown_event_source, _}}`,
      `{:error, {:event_stream_does_not_belong_to_event_source, _, _}}` or
      `{:error, {:event_routing_contradicts_event_source, _, _, _, _}}`

  Omitted, `nil`, and empty routing values travel as empty strings. The kernel
  resolves these to `"Default"` / `"All"` / `"Default"`; nonempty values are exact.
  Concurrency filters are independent of routing and are never filled from it.

  Returns `:ok` on success or `{:error, reason}` on failure, including concurrency
  and validation rejection. Append requests require a successful descriptor
  compatibility check before they are sent. A successful check is shared by all
  callers on that connection until it reconnects. Failed checks are retried on
  the next append.

  The check uses the installed 18.3.0 contract descriptor. It does not yet
  distinguish older kernels from kernels implementing canonical append metadata;
  that requires a future contracts pin carrying the new contract.
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
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case buffer_append(event_sequence_id, event_source_id, event, opts) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    else
      do_append_many(event_sequence_id, event_source_id, events, opts)
    end
  end

  @doc """
  Appends a single event and returns the detailed outcome.

  Unlike `append/3` (which returns `:ok | {:error, term}`), this returns a
  `Chronicle.EventSequences.AppendResult` carrying the assigned sequence number and, on a
  rejection, the structured constraint and concurrency violations:

      case Chronicle.EventSequences.EventLog.append_with_result("acc-1", %Opened{}) do
        {:ok, %{sequence_number: n}} -> n
        {:error, %{constraint_violations: [violation | _]}} -> violation.message
        {:error, %{concurrency_violations: _}} -> :retry
        {:error, other} -> other
      end

  Accepts the options of `append/3`. `{:error, result}` is returned for a kernel rejection;
  transport and client errors are returned as `{:error, reason}` with a non-result term.
  """
  @spec append_with_result(String.t(), struct(), keyword()) ::
          {:ok, AppendResult.t()} | {:error, AppendResult.t() | term()}
  def append_with_result(event_source_id, event, opts \\ []) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    case raw_append(event_sequence_id, event_source_id, event, opts) do
      {:ok, response} -> result_for(response, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Appends events atomically for one event source and returns the detailed outcome with every
  assigned sequence number. See `append_with_result/3`.
  """
  @spec append_many_with_result(String.t(), [struct()], keyword()) ::
          {:ok, AppendResult.t()} | {:error, AppendResult.t() | term()}
  def append_many_with_result(event_source_id, events, opts \\ [])

  def append_many_with_result(_event_source_id, [], _opts),
    do: {:ok, %AppendResult{success?: true}}

  def append_many_with_result(event_source_id, events, opts) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    with {:ok, channel, config} <- resolve_append_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      events_to_append =
        Enum.map(
          events,
          &build_event_for_event_source_id(event_source_id, &1, opts, :append_many)
        )

      with {:ok, events_to_append} <-
             prepare_events(events_to_append, config, namespace, event_sequence_id, opts) do
        request =
          build_append_many_for_event_sources_request(
            config,
            namespace,
            event_sequence_id,
            events_to_append,
            opts
          )

        case EventSequences.Stub.append_many_for_event_sources(channel, request) do
          {:ok, envelope} ->
            with {:ok, response} <- unwrap_append_response(envelope, config) do
              result_for(response, opts)
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp result_for(response, opts) do
    result = AppendResult.from_response(response, opts)

    case normalize_response(response) do
      :ok -> {:ok, result}
      {:error, _reason} -> {:error, %{result | success?: false}}
    end
  end

  @doc """
  Appends a list of `Chronicle.EventSequences.EventForEventSourceId` entries as a
  single atomic append-many, each carrying its own target event source id (and
  other per-event metadata such as stream type/id, subject, tags, and occurred
  time). Identity and causation are batch-level; see
  `Chronicle.EventSequences.EventForEventSourceId` for their precedence.

  Use this when a batch of events needs to target several, possibly different,
  event source ids in one transaction — e.g. reactor side-effect dispatch (see
  `Chronicle.Reactors.Handler`).

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
  """
  @spec append_many_for_event_sources([EventForEventSourceId.t()], keyword()) ::
          :ok | {:error, term()}
  def append_many_for_event_sources(events, opts \\ [])

  def append_many_for_event_sources([], _opts), do: :ok

  def append_many_for_event_sources(events, opts) when is_list(events) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    if UnitOfWork.has_current?() do
      with :ok <- check_event_types(events) do
        Enum.each(events, fn %EventForEventSourceId{} = event ->
          UnitOfWork.add_event(
            UnitOfWork.current(),
            event_sequence_id,
            event,
            client: Keyword.get(opts, :client, Chronicle.Client),
            namespace: Keyword.get(opts, :namespace)
          )
        end)

        :ok
      end
    else
      with {:ok, channel, config} <- resolve_append_channel(opts) do
        namespace = Keyword.get(opts, :namespace, config.namespace)

        with {:ok, events} <-
               prepare_events(
                 DefinitionRouting.apply_defaults(events, opts),
                 config,
                 namespace,
                 event_sequence_id,
                 opts
               ) do
          request =
            build_append_many_for_event_sources_request(
              config,
              namespace,
              event_sequence_id,
              events,
              opts
            )

          case EventSequences.Stub.append_many_for_event_sources(channel, request) do
            {:ok, envelope} ->
              with {:ok, response} <- unwrap_append_response(envelope, config) do
                normalize_response(response)
              end

            {:error, reason} ->
              {:error, reason}
          end
        end
      end
    end
  end

  @doc """
  Appends a single event, then waits for every observer (reactor, reducer, ++)
  affected by the append to either reach the appended sequence number or fail.

  This is additive rather than a change to `append/3`'s return shape: `append/3`
  and `append_many/3` return only `:ok | {:error, term()}` today (no
  `AppendResult`-equivalent carrying a sequence number), so building
  `WaitForCompletion` on top of them would either be a breaking change to their
  return contract or require a second round-trip to re-discover the sequence
  number. This function does the append and the wait as one call instead.

  Mirrors the C# client's `AppendResult.WaitForCompletion()` extension.

  Returns `{:ok, %{success: boolean(), failed_partitions: [Chronicle.FailedPartitions.FailedPartition.t()]}}`
  on success (whether or not every observer completed — check `:success`), or
  `{:error, reason}` if the append itself failed.

  ## Options

  Same as `append/3`, plus:

    * `:timeout` — how long to wait for observer completion, in milliseconds
      (default: `5_000`, matching the C# client's default).
  """
  @spec append_and_wait_for_completion(String.t(), struct(), keyword()) ::
          {:ok, %{success: boolean(), failed_partitions: list()}} | {:error, term()}
  def append_and_wait_for_completion(event_source_id, event, opts \\ []) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    with {:ok, response} <- raw_append(event_sequence_id, event_source_id, event, opts),
         :ok <- normalize_response(response) do
      raw_sequence_number =
        Map.get(response, :SequenceNumber, Map.get(response, :sequence_number, 0))

      if raw_sequence_number == @unavailable_sequence_number do
        {:ok, %{success: true, failed_partitions: []}}
      else
        wait_for_observer_completion(event_sequence_id, raw_sequence_number, opts)
      end
    end
  end

  defp wait_for_observer_completion(event_sequence_id, sequence_number, opts),
    do:
      wait_for_sequence_number(
        sequence_number,
        Keyword.put(opts, :event_sequence_id, event_sequence_id)
      )

  @doc """
  Waits for every observer affected by events up to `sequence_number` to reach it or fail.

  Options: `:client`, `:namespace`, `:event_sequence_id` and `:timeout`.
  Returns `{:ok, %{success: boolean(), failed_partitions: [...]}}`.
  """
  @spec wait_for_sequence_number(non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def wait_for_sequence_number(sequence_number, opts \\ []) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace) || config.namespace
      timeout = Keyword.get(opts, :timeout, @default_wait_for_completion_timeout)

      request =
        struct(WaitForObserverCompletionRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          TailEventSequenceNumber: sequence_number
        )

      case Observers.Stub.wait_for_completion(channel, request, timeout: timeout) do
        {:ok, response} ->
          {:ok,
           %{
             success: Map.get(response, :IsSuccess, false),
             failed_partitions:
               response
               |> Map.get(:FailedPartitions, [])
               |> Enum.map(&Chronicle.FailedPartitions.decode_failed_partition/1)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc false
  @spec buffer_append(String.t(), String.t(), struct(), keyword()) :: :ok | {:error, term()}
  def buffer_append(event_sequence_id, event_source_id, event, opts \\ []) do
    with :ok <- check_event_type(event) do
      buffered_event =
        build_event_for_event_source_id(event_source_id, event, opts, :transactional)

      UnitOfWork.add_event(
        UnitOfWork.current(),
        event_sequence_id,
        buffered_event,
        client: Keyword.get(opts, :client, Chronicle.Client),
        namespace: Keyword.get(opts, :namespace)
      )
    end
  end

  @doc false
  @spec commit_transaction(map()) :: {:ok, map()} | {:error, term()}
  def commit_transaction(%{events: []}) do
    {:ok, UnitOfWork.default_commit_result([], [], [])}
  end

  def commit_transaction(%{event_sequence_id: event_sequence_id, events: events} = state) do
    client = Map.get(state, :client, Chronicle.Client)
    correlation_id = Map.fetch!(state, :correlation_id)

    attributes =
      append_span_attributes(client, event_sequence_id, nil, correlation_id: correlation_id)
      |> Map.put("cratis.event.count", length(events))

    Tracing.with_telemetry_span(
      [:cratis, :chronicle, :client, :append],
      %{event_sequence_id: event_sequence_id, event_count: length(events)},
      "cratis.chronicle.client.event_sequence.append_many",
      Map.put(attributes, :kind, :client),
      fn ->
        with {:ok, channel, config} <- resolve_append_channel(client: client) do
          namespace = Map.get(state, :namespace) || config.namespace

          with {:ok, events} <-
                 prepare_events(events, config, namespace, event_sequence_id,
                   client: client,
                   namespace: namespace,
                   guarded_event_sources: state |> Map.get(:decision_reads, %{}) |> Map.keys()
                 ) do
            request =
              build_append_many_for_event_sources_request(
                config,
                namespace,
                event_sequence_id,
                events,
                correlation_id: correlation_id,
                causation: batch_causation(events),
                identity: batch_identity(events),
                decision_read_scopes: decision_read_scope_entries(state)
              )

            commit_request(channel, request, config)
          end
        end
      end
    )
  end

  defp commit_request(channel, request, config) do
    case EventSequences.Stub.append_many_for_event_sources(channel, request) do
      {:ok, envelope} ->
        with {:ok, response} <- unwrap_append_response(envelope, config) do
          response_data = if is_map(response), do: response, else: %{}

          result =
            UnitOfWork.default_commit_result(
              get_sequence_numbers(response_data),
              Map.get(
                response_data,
                :ConstraintViolations,
                Map.get(response_data, :constraint_violations, [])
              ),
              Map.get(response_data, :Errors, Map.get(response_data, :errors, []))
            )

          case normalize_response(response) do
            :ok -> {:ok, result}
            {:error, reason} -> {:ok, %{result | success?: false, error: reason}}
          end
        end

      {:error, reason} ->
        {:error, reason}
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

    * `:decode` — when `true`, returns `Chronicle.Events.AppendedEvent` structs whose `:event`
      is the event struct (default: `false`, the raw wire events)

  Returns `{:ok, [appended_event]}` or `{:error, reason}`.
  """
  @spec get_for_event_source(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_for_event_source(event_source_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])

      event_type_ids = join_event_type_ids(event_type_modules)

      request =
        struct(ForEventSourceIdAndEventTypesRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceId: event_source_id,
          EventStreamType: Keyword.get(opts, :event_stream_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, ""),
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventTypeIds: event_type_ids
        )

      case EventSequences.Stub.for_event_source_id_and_event_types(channel, request) do
        {:ok, envelope} -> envelope |> WireResult.unwrap() |> maybe_decode(config, opts)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # With `decode: true` the wire events become `Chronicle.Events.AppendedEvent` structs whose
  # `:event` is the registered event struct. The `:event_types` option (used for filtering) and the
  # client's registered event types are both searched.
  defp maybe_decode({:ok, events}, config, opts) when is_list(events) do
    if Keyword.get(opts, :decode, false) do
      event_types =
        Enum.uniq(Keyword.get(opts, :event_types, []) ++ Map.get(config, :event_types, []))

      {:ok, Enum.map(events, &Chronicle.Events.AppendedEvent.from_wire(&1, event_types))}
    else
      {:ok, events}
    end
  end

  defp maybe_decode(other, _config, _opts), do: other

  @doc """
  Returns events from (and including) the given sequence number onward.

  Mirrors the Chronicle C# and TypeScript clients' `GetFromSequenceNumber()`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:event_source_id` — optional event source id to filter by (default: all)
    * `:event_types` — list of event type modules to filter by (default: all)
    * `:decode` — when `true`, returns `Chronicle.Events.AppendedEvent` structs whose `:event`
      is the event struct (default: `false`, the raw wire events)

  Returns `{:ok, [appended_event]}` or `{:error, reason}`.
  """
  @spec get_from_sequence_number(non_neg_integer(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_from_sequence_number(sequence_number, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])
      event_type_ids = join_event_type_ids(event_type_modules)

      request =
        struct(FromSequenceNumberRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          FromEventSequenceNumber: sequence_number,
          EventSourceId: Keyword.get(opts, :event_source_id, ""),
          EventTypeIds: event_type_ids
        )

      case EventSequences.Stub.from_sequence_number(channel, request) do
        {:ok, envelope} -> envelope |> WireResult.unwrap() |> maybe_decode(config, opts)
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
    * `:event_source_type` — the event source type to filter by (default: all)
    * `:event_stream_type` — the event stream type to filter by (default: all)
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

      # CompleteStream answers with a command-result envelope whose payload carries IsSuccess.
      with {:ok, envelope} <- EventSequences.Stub.complete_stream(channel, request),
           {:ok, response} <- WireResult.unwrap(envelope) do
        decode_complete_stream_response(response)
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

      # The kernel wraps the answer in a query result envelope; HasEvents lives on its Data.
      case EventSequences.Stub.has_events_for_event_source_id(channel, request) do
        {:ok, envelope} ->
          with {:ok, data} <- WireResult.unwrap(envelope) do
            {:ok, has_events?(data)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp has_events?(%{} = data),
    do: Map.get(data, :HasEvents, Map.get(data, :has_events, false)) == true

  defp has_events?(_), do: false

  @doc """
  Serializes `event` once and returns a `Chronicle.EventSequences.PreparedEvent` bound to this
  client, namespace and event sequence, for reuse with `append_prepared/3` and
  `Chronicle.EventSequences.Streams.verify_content/3`. Mutating `event` afterward has no effect -
  the content was captured at preparation time.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)

  Returns `{:error, {:unknown_event_type, module}}` when `event` does not
  `use Chronicle.Events.EventType`.
  """
  @spec prepare(struct(), keyword()) :: {:ok, PreparedEvent.t()} | {:error, term()}
  def prepare(event, opts \\ []) do
    with :ok <- check_event_type(event) do
      client = Keyword.get(opts, :client, Chronicle.Client)

      case Chronicle.Client.config(client) do
        config when is_map(config) ->
          namespace = Keyword.get(opts, :namespace, config.namespace)
          event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

          {:ok,
           %PreparedEvent{
             owner: {client, namespace, event_sequence_id},
             event: event,
             event_type: build_event_type(event),
             content: encode_event(event)
           }}

        _ ->
          {:error, :no_client}
      end
    end
  end

  @doc """
  Appends a `prepare/2`d event. Accepts the options of `append/3`. The event was serialized once,
  at preparation time - this never re-serializes it.

  Returns `{:error, :prepared_event_belongs_to_another_sequence}` when `prepared_event` was
  prepared for a different client, namespace, or event sequence than this call targets.
  """
  @spec append_prepared(String.t(), PreparedEvent.t(), keyword()) :: :ok | {:error, term()}
  def append_prepared(event_source_id, %PreparedEvent{} = prepared_event, opts \\ []) do
    event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
    client = Keyword.get(opts, :client, Chronicle.Client)

    with :ok <-
           check_prepared_owner(
             prepared_event,
             client,
             Keyword.get(opts, :namespace),
             event_sequence_id
           ) do
      if UnitOfWork.has_current?() do
        buffer_append_prepared(event_sequence_id, event_source_id, prepared_event, opts)
      else
        do_append_prepared(event_sequence_id, event_source_id, prepared_event, opts)
      end
    end
  end

  defp check_prepared_owner(
         %PreparedEvent{owner: owner},
         client,
         namespace_opt,
         event_sequence_id
       ) do
    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        namespace = namespace_opt || config.namespace

        if owner == {client, namespace, event_sequence_id} do
          :ok
        else
          {:error, :prepared_event_belongs_to_another_sequence}
        end

      _ ->
        {:error, :no_client}
    end
  end

  defp do_append_prepared(event_sequence_id, event_source_id, prepared_event, opts) do
    event_to_append =
      build_prepared_event_for_event_source_id(event_source_id, prepared_event, opts, :append)

    do_append_event(event_sequence_id, event_to_append, opts)
  end

  defp buffer_append_prepared(event_sequence_id, event_source_id, prepared_event, opts) do
    event_to_append =
      build_prepared_event_for_event_source_id(
        event_source_id,
        prepared_event,
        opts,
        :transactional
      )

    UnitOfWork.add_event(
      UnitOfWork.current(),
      event_sequence_id,
      event_to_append,
      client: Keyword.get(opts, :client, Chronicle.Client),
      namespace: Keyword.get(opts, :namespace)
    )
  end

  defp build_prepared_event_for_event_source_id(event_source_id, prepared_event, opts, mode) do
    event_source_id
    |> build_event_for_event_source_id(prepared_event.event, opts, mode)
    |> Map.put(:prepared, %{
      event_type: prepared_event.event_type,
      content: prepared_event.content
    })
  end

  defp do_append(event_sequence_id, event_source_id, event, opts) do
    event_to_append = build_event_for_event_source_id(event_source_id, event, opts, :append)
    do_append_event(event_sequence_id, event_to_append, opts)
  end

  defp do_append_event(event_sequence_id, event_to_append, opts) do
    case raw_append_event(event_sequence_id, event_to_append, opts) do
      {:ok, response} -> normalize_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  # Performs the append and returns the raw, un-normalized gRPC response
  # (still carrying the assigned SequenceNumber), so callers that need it —
  # like append_and_wait_for_completion/3 — don't have to duplicate the
  # request-building logic.
  defp raw_append(event_sequence_id, event_source_id, event, opts) do
    event_to_append = build_event_for_event_source_id(event_source_id, event, opts, :append)
    raw_append_event(event_sequence_id, event_to_append, opts)
  end

  defp raw_append_event(event_sequence_id, event_to_append, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    attributes =
      append_span_attributes(client, event_sequence_id, event_to_append.event_source_id, opts)
      |> Map.put("cratis.event_type.id", event_type_id(event_to_append.event))

    Tracing.with_telemetry_span(
      [:cratis, :chronicle, :client, :append],
      %{event_sequence_id: event_sequence_id, event_count: 1},
      "cratis.chronicle.client.event_sequence.append",
      Map.put(attributes, :kind, :client),
      fn ->
        with {:ok, channel, config} <- resolve_append_channel(opts) do
          namespace = Keyword.get(opts, :namespace, config.namespace)

          with {:ok, [event_to_append]} <-
                 prepare_events([event_to_append], config, namespace, event_sequence_id, opts) do
            send_append(channel, config, namespace, event_sequence_id, event_to_append, opts)
          end
        end
      end
    )
  end

  # Attributes common to every event-sequence span, per the shared Cratis
  # OpenTelemetry convention (Cratis/Architecture#33). `cratis.event_source.id`
  # is only added when `Chronicle.Diagnostics.Tracing.trace_event_source_id?/0`
  # is on, since an event source id can itself be sensitive (D7).
  defp append_span_attributes(client, event_sequence_id, event_source_id, opts) do
    config = Chronicle.Client.config(client)

    base = %{
      "cratis.event_sequence.id" => event_sequence_id,
      "cratis.correlation_id" => correlation_id_attribute(opts)
    }

    base =
      if is_map(config) do
        base
        |> Map.put("cratis.event_store.name", config.event_store)
        |> Map.put(
          "cratis.event_store.namespace",
          Keyword.get(opts, :namespace, config.namespace)
        )
      else
        base
      end

    if event_source_id != nil and Tracing.trace_event_source_id?() do
      Map.put(base, "cratis.event_source.id", to_string(event_source_id))
    else
      base
    end
  end

  defp correlation_id_attribute(opts) do
    case Keyword.get(opts, :correlation_id) do
      %CorrelationId{value: value} -> value
      id when is_binary(id) -> id
      _ -> CorrelationIdManager.current().value
    end
  end

  defp event_type_id(event) do
    module = event.__struct__

    if function_exported?(module, :__chronicle_event_type__, 1) do
      module.__chronicle_event_type__(:id)
    else
      ""
    end
  end

  defp send_append(channel, config, namespace, event_sequence_id, event_to_append, opts) do
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
        EventType: prepared_event_type(event_to_append),
        Content: prepared_content(event_to_append),
        Causation: causation_entries_to_proto(event_to_append.causation),
        CausedBy: identity_to_proto(event_to_append.identity),
        ConcurrencyScope: build_concurrency_scope(event_to_append.concurrency_scope),
        Occurred: datetime_offset_for(event_to_append.occurred),
        Tags: event_to_append.tags || [],
        Subject: event_to_append.subject || "",
        EventSource: event_source_name(event_to_append)
      )

    case EventSequences.Stub.append(channel, request) do
      {:ok, envelope} -> unwrap_append_response(envelope, config)
      {:error, reason} -> {:error, reason}
    end
  end

  # A `prepare/2`d event already carries its serialized content and event type - captured once,
  # at preparation time - so sending it never re-serializes the event.
  defp prepared_event_type(%EventForEventSourceId{prepared: %{event_type: event_type}}),
    do: event_type

  defp prepared_event_type(%EventForEventSourceId{event: event}), do: build_event_type(event)

  defp prepared_content(%EventForEventSourceId{prepared: %{content: content}}), do: content
  defp prepared_content(%EventForEventSourceId{event: event}), do: encode_event(event)

  # Only appends that went through a definition claim registered-source metadata;
  # legacy appends leave the wire field unset rather than inventing a name.
  defp event_source_name(%EventForEventSourceId{routing: nil}), do: nil

  defp event_source_name(%EventForEventSourceId{routing: routing}),
    do: Chronicle.EventSources.Routing.event_source(routing)

  defp prepare_events(events, config, namespace, event_sequence_id, opts) do
    events = Enum.map(events, &apply_event_type_defaults/1)

    with :ok <- check_event_types(events),
         :ok <- validate_concurrency_scopes(events),
         :ok <- check_payload_size(events) do
      resolve_events(events, config, namespace, event_sequence_id, opts)
    end
  end

  defp check_event_types(events) do
    Enum.find_value(events, :ok, fn %EventForEventSourceId{event: event} ->
      case check_event_type(event) do
        :ok -> nil
        {:error, _} = error -> error
      end
    end)
  end

  defp check_event_type(%module{}) do
    if ClientEventType.event_type?(module) do
      :ok
    else
      {:error, {:unknown_event_type, module}}
    end
  end

  # The wire carries one concurrency scope per event source id (first-declared-wins), so two
  # explicit, unequal scopes for the same id would silently drop one. Equal duplicates (the same
  # guard declared more than once) are harmless and allowed.
  defp validate_concurrency_scopes(events) do
    events
    |> Enum.filter(&(&1.concurrency_scope != nil))
    |> Enum.group_by(& &1.event_source_id)
    |> Enum.find_value(:ok, fn {event_source_id, group} ->
      normalized =
        group |> Enum.map(&ClientConcurrencyScope.normalize(&1.concurrency_scope)) |> Enum.uniq()

      if length(normalized) > 1 do
        {:error, {:duplicate_concurrency_scope, event_source_id}}
      end
    end)
  end

  # An event type may declare the field holding its data subject and static tags
  # (see Chronicle.Events.EventType). An explicit subject always wins, tags are merged.
  defp apply_event_type_defaults(%EventForEventSourceId{event: event} = entry) do
    subject =
      if entry.subject in [nil, ""],
        do: Chronicle.Events.EventType.declared_subject(event) || entry.subject,
        else: entry.subject

    tags = Enum.uniq((entry.tags || []) ++ Chronicle.Events.EventType.declared_tags(event))
    %{entry | subject: subject, tags: tags}
  end

  # Refuses a batch the kernel would reject with ResourceExhausted before it can break the
  # shared connection. See Chronicle.PayloadLimit.
  defp check_payload_size(events) do
    if Chronicle.PayloadLimit.limit() == :infinity do
      :ok
    else
      events
      |> Enum.map(&prepared_content/1)
      |> Chronicle.PayloadLimit.check_all()
    end
  end

  defp resolve_events(events, config, namespace, event_sequence_id, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    tail_opts = [client: client, namespace: namespace, event_sequence_id: event_sequence_id]

    with {:ok, events} <- resolve_definition_routed_concurrency(events, config, tail_opts) do
      ConcurrencyStrategy.apply_default(
        events,
        config,
        fn event_source_id, narrowing ->
          raw_tail_sequence_number(event_source_id, tail_opts ++ narrowing)
        end, guarded_event_sources: Keyword.get(opts, :guarded_event_sources, []))
    end
  end

  defp resolve_definition_routed_concurrency(events, config, tail_opts) do
    if DefinitionRouting.used?(events) do
      with {:ok, resolved} <-
             DefinitionRouting.resolve(events, Map.get(config, :event_sources, [])) do
        DefinitionRouting.apply_concurrency(resolved, fn event_source_id, narrowing ->
          raw_tail_sequence_number(event_source_id, tail_opts ++ narrowing)
        end)
      end
    else
      {:ok, events}
    end
  end

  defp do_append_many(event_sequence_id, event_source_id, events, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    attributes =
      append_span_attributes(client, event_sequence_id, event_source_id, opts)
      |> Map.put("cratis.event.count", length(events))

    Tracing.with_telemetry_span(
      [:cratis, :chronicle, :client, :append],
      %{event_sequence_id: event_sequence_id, event_count: length(events)},
      "cratis.chronicle.client.event_sequence.append_many",
      Map.put(attributes, :kind, :client),
      fn ->
        with {:ok, channel, config} <- resolve_append_channel(opts) do
          namespace = Keyword.get(opts, :namespace, config.namespace)

          events_to_append =
            Enum.map(events, fn event ->
              build_event_for_event_source_id(event_source_id, event, opts, :append_many)
            end)

          with {:ok, events_to_append} <-
                 prepare_events(events_to_append, config, namespace, event_sequence_id, opts) do
            request =
              build_append_many_for_event_sources_request(
                config,
                namespace,
                event_sequence_id,
                events_to_append,
                opts
              )

            case EventSequences.Stub.append_many_for_event_sources(channel, request) do
              {:ok, envelope} ->
                with {:ok, response} <- unwrap_append_response(envelope, config) do
                  normalize_response(response)
                end

              {:error, reason} ->
                {:error, reason}
            end
          end
        end
      end
    )
  end

  defp build_append_many_for_event_sources_request(
         config,
         namespace,
         event_sequence_id,
         events,
         opts
       ) do
    normalized_events = Enum.map(events, &normalize_event_for_batch/1)

    request =
      struct(AppendManyForEventSourcesRequest,
        EventStore: config.event_store,
        Namespace: namespace,
        EventSequenceId: event_sequence_id,
        Events: Enum.map(normalized_events, &event_for_event_source_to_proto/1)
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
      batch_identity(normalized_events) || Keyword.get(opts, :identity) || build_identity(opts)
    )
    |> maybe_put(
      :ConcurrencyScopes,
      Keyword.get(opts, :decision_read_scopes, []) ++
        build_concurrency_scope_entries(normalized_events)
    )
  end

  # A decision read (Chronicle.ReadModels.DecisionReads) guards an event source whether or not
  # the unit of work appends anything to it directly - unlike an event's own concurrency scope,
  # which only exists because that event is in the batch. Chronicle.Transactions.UnitOfWork
  # refuses to enroll both for the same event source, so these two sets never collide.
  defp decision_read_scope_entries(state) do
    state
    |> Map.get(:decision_reads, %{})
    |> Enum.map(fn {event_source_id, scope} ->
      struct(EventSourceConcurrencyScope,
        EventSourceId: event_source_id,
        Scope: build_concurrency_scope(scope)
      )
    end)
  end

  # Routing omission stays on the wire; only the kernel chooses routing defaults.
  defp normalize_event_for_batch(%EventForEventSourceId{} = event) do
    %{
      event
      | event_source_type: event.event_source_type || "",
        event_stream_type: event.event_stream_type || "",
        event_stream_id: event.event_stream_id || "",
        causation: normalize_batch_causation(event.causation),
        identity: event.identity || build_identity([])
    }
  end

  defp normalize_batch_causation([]),
    do: CausationManager.get_current_chain() ++ [client_causation_for_mode(:append_many)]

  defp normalize_batch_causation(causation), do: causation

  defp build_event_for_event_source_id(event_source_id, event, opts, mode) do
    %EventForEventSourceId{
      event_source_id: event_source_id,
      event: event,
      event_source_type: Keyword.get(opts, :event_source_type) || "",
      event_stream_type: Keyword.get(opts, :event_stream_type) || "",
      event_stream_id: Keyword.get(opts, :event_stream_id) || "",
      tags: Keyword.get(opts, :tags, []),
      subject: Keyword.get(opts, :subject, ""),
      occurred: Keyword.get(opts, :occurred),
      concurrency_scope: Keyword.get(opts, :concurrency_scope),
      event_source: Keyword.get(opts, :event_source),
      event_stream: Keyword.get(opts, :event_stream),
      causation: build_causation_entries(opts, mode),
      identity: build_identity(opts)
    }
  end

  # Rich entries preserve routing, tags, subject, and occurred time for every batch.
  defp event_for_event_source_to_proto(%EventForEventSourceId{} = event_to_append) do
    event =
      struct(WireEventForEventSourceId,
        EventSourceId: event_to_append.event_source_id,
        EventSourceType: event_to_append.event_source_type,
        EventStreamType: event_to_append.event_stream_type,
        EventStreamId: event_to_append.event_stream_id,
        EventType: build_event_type(event_to_append.event),
        Content: encode_event(event_to_append.event),
        Tags: event_to_append.tags || []
      )

    event
    |> maybe_put(:Occurred, datetime_offset_for(event_to_append.occurred))
    |> maybe_put(:Subject, event_to_append.subject || "")
    |> maybe_put(:EventSource, event_source_name(event_to_append))
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

  # Event type filters travel as a single comma-joined id string on the wire,
  # not a repeated EventType list.
  defp join_event_type_ids(event_type_modules) do
    event_type_modules
    |> Enum.map(& &1.__chronicle_event_type__(:id))
    |> Enum.join(",")
  end

  defp resolve_append_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    resolve_channel_for_client(client, &Connection.append_channel/1)
  end

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    resolve_channel_for_client(client)
  end

  defp resolve_channel_for_client(client, channel_for \\ &Connection.channel/1) do
    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case channel_for.(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end

  defp encode_event(event), do: Chronicle.Serialization.to_json(event, :camel)

  defp build_correlation_id(opts) do
    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        %CorrelationId{} = id -> id
        id when is_binary(id) -> CorrelationId.new(id)
        _ -> CorrelationIdManager.current()
      end

    # protobuf-net Guid carries Guid.ToByteArray() in two little-endian words.
    <<first::32, second::16, third::16, remaining::binary-size(8)>> =
      correlation_id.value |> String.replace("-", "") |> Base.decode16!(case: :mixed)

    <<lo::little-64, hi::little-64>> =
      <<first::little-32, second::little-16, third::little-16, remaining::binary>>

    struct(BclGuid, lo: lo, hi: hi)
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

  defp build_concurrency_scope(nil), do: nil

  defp build_concurrency_scope(scope_or_opts) do
    scope = ClientConcurrencyScope.normalize(scope_or_opts)

    struct(ContractConcurrencyScope)
    |> maybe_put(:SequenceNumber, scope.sequence_number)
    |> maybe_put(:EventSourceId, scope.event_source_id)
    |> maybe_put(:EventStreamType, scope.event_stream_type)
    |> maybe_put(:EventStreamId, scope.event_stream_id)
    |> maybe_put(:EventSourceType, scope.event_source_type)
    |> maybe_put(:EventTypes, Enum.map(scope.event_types, &build_event_type_for_module/1))
    |> maybe_put(:ExpectsNoMatchingEvent, scope.expects_no_matching_event)
  end

  defp current_datetime_offset do
    datetime_offset_for(DateTime.utc_now())
  end

  defp datetime_offset_for(nil), do: nil

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

  # AppendManyForEventSourcesRequest.ConcurrencyScopes is a repeated list of
  # {EventSourceId, Scope} entries, not a map - one entry per distinct event source
  # that declared a scope, first-declared-wins for an event source repeated in the batch.
  defp build_concurrency_scope_entries(events) do
    events
    |> Enum.reduce([], fn %EventForEventSourceId{} = event, acc ->
      cond do
        is_nil(event.concurrency_scope) ->
          acc

        Enum.any?(acc, fn entry -> Map.get(entry, :EventSourceId) == event.event_source_id end) ->
          acc

        true ->
          [
            struct(EventSourceConcurrencyScope,
              EventSourceId: event.event_source_id,
              Scope: build_concurrency_scope(event.concurrency_scope)
            )
            | acc
          ]
      end
    end)
    |> Enum.reverse()
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

  defp unwrap_append_response(envelope, config) do
    with {:ok, response} <- WireResult.unwrap(envelope) do
      {:ok,
       AppendResponse.resolve_messages(
         response,
         Map.get(config, :event_types, []),
         Map.get(config, :constraints, [])
       )}
    end
  end

  defp normalize_response(response), do: AppendResponse.normalize(response)

  defp get_sequence_numbers(response) do
    response
    |> Map.get(:SequenceNumbers, Map.get(response, :sequence_numbers, []))
    |> Enum.map(&normalize_sequence_number/1)
  end

  defp normalize_sequence_number(@unavailable_sequence_number), do: 0
  defp normalize_sequence_number(value) when is_integer(value) and value >= 0, do: value
  defp normalize_sequence_number(_), do: 0

  # Fetches the tail sequence number without collapsing the "unavailable" sentinel,
  # so callers that need to distinguish "no tail" from "tail at 0" (like
  # get_next_sequence_number/2, and Chronicle.ReadModels.DecisionReads's probe/boundary
  # comparison) can do so. Public (but @doc false) for that cross-module use.
  @doc false
  @spec raw_tail_sequence_number(String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def raw_tail_sequence_number(event_source_id, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)
      event_type_modules = Keyword.get(opts, :event_types, [])
      event_type_ids = join_event_type_ids(event_type_modules)

      request =
        struct(TailSequenceNumberRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          EventSequenceId: event_sequence_id,
          EventSourceId: event_source_id || "",
          EventTypeIds: event_type_ids,
          # An omitted dimension stays empty so the lookup isn't narrowed to the legacy
          # "Default" route, which matches no event appended without an explicit route.
          EventSourceType: Keyword.get(opts, :event_source_type, ""),
          EventStreamId: Keyword.get(opts, :event_stream_id, ""),
          EventStreamType: Keyword.get(opts, :event_stream_type, "")
        )

      case EventSequences.Stub.tail_sequence_number(channel, request) do
        {:ok, envelope} ->
          with {:ok, data} <- WireResult.unwrap(envelope) do
            {:ok, Map.get(data, :SequenceNumber, Map.get(data, :sequence_number, 0))}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Returns the event type modules a reactor or reducer module subscribes to,
  # via its `@handles` declarations. Public (but @doc false) so it can be
  # exercised directly in tests without a live connection.
  @doc false
  @spec observer_event_types(module()) :: [module()]
  def observer_event_types(module) do
    cond do
      function_exported?(module, :__chronicle_reactor__, 1) ->
        module.__chronicle_reactor__(:handles)

      function_exported?(module, :__chronicle_reducer__, 1) ->
        module.__chronicle_reducer__(:handles)

      true ->
        []
    end
  end

  # Decodes complete_stream/3's wire error into a typed atom. Public (but
  # @doc false) so it can be exercised directly in tests without a live
  # connection.
  @doc false
  def decode_complete_stream_response(response) do
    if Map.get(response, :IsSuccess, false) do
      {:ok, normalize_sequence_number(Map.get(response, :SequenceNumber, 0))}
    else
      {:error, decode_complete_stream_error(Map.get(response, :Error))}
    end
  end

  @doc false
  @spec decode_complete_stream_error(term()) ::
          :default_stream_cannot_be_completed
          | :already_completed
          | :empty_scope
          | :expected_tail_mismatch
  def decode_complete_stream_error(:DefaultStreamCannotBeCompleted),
    do: :default_stream_cannot_be_completed

  def decode_complete_stream_error(:EmptyScope), do: :empty_scope
  def decode_complete_stream_error(:ExpectedTailMismatch), do: :expected_tail_mismatch

  def decode_complete_stream_error(_), do: :already_completed
end
