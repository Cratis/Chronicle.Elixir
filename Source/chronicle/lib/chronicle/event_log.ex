# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventLog do
  @moduledoc """
  Appends and queries events in a Chronicle event log.

  The event log is the primary `EventSequence` in Chronicle. Use `append/3` to
  record domain events for a given event source (such as an aggregate root).

  ## Usage

      :ok = Chronicle.EventLog.append("account-1", %MyApp.Events.AccountOpened{
        account_id: "account-1",
        owner_name: "Alice",
        initial_balance: 500
      })

  To append to a specific client:

      :ok = Chronicle.EventLog.append("account-1", event, client: :my_chronicle)

  ## Multiple events

      events = [
        %MyApp.Events.AccountOpened{account_id: "1", owner_name: "Alice"},
        %MyApp.Events.FundsDeposited{account_id: "1", amount: 500}
      ]
      :ok = Chronicle.EventLog.append_many("account-1", events)
  """

  alias Cratis.Chronicle.Contracts.EventSequences.{
    EventSequences,
    AppendRequest,
    AppendManyRequest,
    EventToAppend,
    EventType,
    Causation,
    ConcurrencyScope,
    Identity,
    SerializableDateTimeOffset,
    GetForEventSourceIdAndEventTypesRequest
  }

  alias Chronicle.Connections.Connection

  # Bcl.Guid used for CorrelationId in AppendRequest
  alias Bcl.Guid, as: BclGuid

  @event_log_id "event-log"

  @doc """
  Appends a single event to the event log for the given event source.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_source_type` — the event source type (default: `""`)
    * `:event_stream_type` — the event stream type (default: `""`)
    * `:event_stream_id` — the event stream ID (default: `""`)
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  def append(event_source_id, event, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_module = event.__struct__

      request = struct(AppendRequest,
        CorrelationId: struct(BclGuid),
        EventStore: config.event_store,
        Namespace: namespace,
        EventSequenceId: @event_log_id,
        EventSourceType: Keyword.get(opts, :event_source_type, "Default"),
        EventSourceId: event_source_id,
        EventStreamType: Keyword.get(opts, :event_stream_type, "All"),
        EventStreamId: Keyword.get(opts, :event_stream_id, "Default"),
        EventType: struct(EventType,
          Id: event_module.__chronicle_event_type__(:id),
          Generation: event_module.__chronicle_event_type__(:generation)
        ),
        Content: encode_event(event),
        Causation: [client_causation()],
        CausedBy: struct(Identity, Subject: "elixir-client", Name: "Chronicle Elixir Client", UserName: "chronicle"),
        ConcurrencyScope: struct(ConcurrencyScope, SequenceNumber: 18_446_744_073_709_551_615),
        Occurred: current_datetime_offset(),
        Tags: Keyword.get(opts, :tags, []),
        Subject: Keyword.get(opts, :subject, "")
      )

      case EventSequences.Stub.append(channel, request) do
        {:ok, response} ->
          violations = Map.get(response, :ConstraintViolations, [])
          errors = Map.get(response, :Errors, [])

          cond do
            violations != [] -> {:error, {:constraint_violations, violations}}
            errors != [] -> {:error, {:append_errors, errors}}
            true -> :ok
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Appends multiple events to the event log for the given event source.

  All events are appended atomically. Each event must be a struct that
  `use Chronicle.EventType`.

  ## Options

  Same as `append/3`.
  """
  @spec append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  def append_many(event_source_id, events, opts \\ []) when is_list(events) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      event_entries =
        Enum.map(events, fn event ->
          module = event.__struct__

          struct(EventToAppend,
            EventSourceType: Keyword.get(opts, :event_source_type, "Default"),
            EventSourceId: event_source_id,
            EventStreamType: Keyword.get(opts, :event_stream_type, "All"),
            EventStreamId: Keyword.get(opts, :event_stream_id, "Default"),
            EventType: struct(EventType,
              Id: module.__chronicle_event_type__(:id),
              Generation: module.__chronicle_event_type__(:generation)
            ),
            Content: encode_event(event),
            Tags: Keyword.get(opts, :tags, [])
          )
        end)

      request = struct(AppendManyRequest,
        EventStore: config.event_store,
        Namespace: namespace,
        EventSequenceId: @event_log_id,
        Events: event_entries
      )

      case EventSequences.Stub.append_many(channel, request) do
        {:ok, response} ->
          violations = Map.get(response, :ConstraintViolations, [])
          errors = Map.get(response, :Errors, [])

          cond do
            violations != [] -> {:error, {:constraint_violations, violations}}
            errors != [] -> {:error, {:append_errors, errors}}
            true -> :ok
          end

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
    * `:event_types` — list of event type modules to filter by (default: all)

  Returns `{:ok, [appended_event]}` or `{:error, reason}`.
  """
  @spec get_for_event_source(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_for_event_source(event_source_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_type_modules = Keyword.get(opts, :event_types, [])

      event_types =
        Enum.map(event_type_modules, fn module ->
          struct(EventType,
            Id: module.__chronicle_event_type__(:id),
            Generation: module.__chronicle_event_type__(:generation)
          )
        end)

      request = struct(GetForEventSourceIdAndEventTypesRequest,
        EventStore: config.event_store,
        Namespace: namespace,
        EventSequenceId: @event_log_id,
        EventSourceId: event_source_id,
        EventTypes: event_types
      )

      case EventSequences.Stub.get_for_event_source_id_and_event_types(channel, request) do
        {:ok, response} -> {:ok, Map.get(response, :Events, [])}
        {:error, reason} -> {:error, reason}
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

  defp encode_event(event) do
    event
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {snake_to_camel(Atom.to_string(k)), v} end)
    |> Map.new()
    |> Jason.encode!()
  end

  defp snake_to_camel(snake) do
    [head | tail] = String.split(snake, "_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end

  defp client_causation do
    struct(Causation,
      Type: "Elixir.Chronicle.Client",
      Occurred: current_datetime_offset()
    )
  end

  defp current_datetime_offset do
    struct(SerializableDateTimeOffset, Value: DateTime.utc_now() |> DateTime.to_iso8601())
  end
end
