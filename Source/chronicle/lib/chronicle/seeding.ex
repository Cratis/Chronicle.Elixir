# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Seeding do
  @moduledoc """
  Accumulates and registers seed events with Chronicle.

  This module provides a builder API for accumulating events during seeder
  discovery, then organizing and sending them to the Chronicle server.

  ## Usage

  Typically used within a `Chronicle.Seeding.Seeder.seed/1` callback:

      def seed(builder) do
        builder
        |> Chronicle.Seeding.for(MyEvent, "aggregate-1", [%MyEvent{...}])
        |> Chronicle.Seeding.for_event_source("aggregate-2", [%Event1{...}, %Event2{...}])
      end

  ## Lifecycle

  1. **Discovery** — `discover/2` finds all seeder modules
  2. **Accumulation** — Each seeder's `seed/1` is called, populating the builder
  3. **Registration** — `register/1` organizes entries and sends them to Chronicle

  Events are organized by:
    * Global vs. namespaced
    * Event type and event source (dual organization for server efficiency)
  """

  @type event_source_id :: String.t()
  @type namespace :: String.t()

  @type seeding_entry :: %{
          event_source_id: event_source_id(),
          event_type_id: String.t(),
          event: struct(),
          tags: [String.t()],
          is_global: boolean(),
          target_namespace: namespace() | nil
        }

  @type has_events_for_fun ::
          (event_source_id(), keyword() -> {:ok, boolean()} | {:error, term()})
  @type append_many_fun :: (event_source_id(), [struct()], keyword() -> :ok | {:error, term()})

  @type t :: %__MODULE__{
          entries: [seeding_entry()],
          event_types: module(),
          connection: atom(),
          event_store: String.t(),
          namespace: String.t(),
          client: atom() | nil,
          has_events_for: has_events_for_fun() | nil,
          append_many: append_many_fun() | nil
        }

  defstruct entries: [],
            event_types: nil,
            connection: nil,
            event_store: nil,
            namespace: nil,
            client: nil,
            has_events_for: nil,
            append_many: nil

  @doc """
  Discovers seeder modules and invokes them to populate the builder.

  Iterates through all provided seeder modules, instantiates each, calls
  `seed/1`, and accumulates their events.

  Returns the populated builder struct.
  """
  @spec discover(t(), [module()]) :: t()
  def discover(%__MODULE__{} = builder, seeder_modules) when is_list(seeder_modules) do
    Enum.reduce(seeder_modules, builder, fn module, acc ->
      try do
        case module.seed(acc) do
          %__MODULE__{} = updated ->
            updated

          :ok ->
            acc

          other ->
            raise "Seeder #{inspect(module)} returned #{inspect(other)}, expected builder or :ok"
        end
      rescue
        e ->
          require Logger
          Logger.warning("Failed to execute seeder #{inspect(module)}: #{Exception.message(e)}")
          acc
      end
    end)
  end

  @doc """
  Seeds events of a specific type for an event source.

  ## Parameters

    * `builder` — the seeding builder
    * `event_type` — the event type module (must `use Chronicle.Events.EventType`)
    * `event_source_id` — the event source (aggregate) ID
    * `events` — list of event structs

  ## Example

      builder
      |> Chronicle.Seeding.for(MyApp.Events.AccountOpened, "account-1", [
        %MyApp.Events.AccountOpened{account_id: "account-1", owner_name: "Alice"}
      ])
  """
  @spec for(t(), module(), event_source_id(), [struct()]) :: t()
  def for(%__MODULE__{} = builder, event_type, event_source_id, events)
      when is_atom(event_type) and is_binary(event_source_id) and is_list(events) do
    event_type_id = event_type.__chronicle_event_type__(:id)

    entries =
      Enum.map(events, fn event ->
        tags = extract_tags(event)

        %{
          event_source_id: event_source_id,
          event_type_id: event_type_id,
          event: event,
          tags: tags,
          is_global: true,
          target_namespace: nil
        }
      end)

    %{builder | entries: builder.entries ++ entries}
  end

  @doc """
  Seeds multiple event types for a single event source.

  ## Parameters

    * `builder` — the seeding builder
    * `event_source_id` — the event source (aggregate) ID
    * `events` — list of event structs (can be different types)

  ## Example

      builder
      |> Chronicle.Seeding.for_event_source("account-1", [
        %MyApp.Events.AccountOpened{account_id: "account-1", owner_name: "Alice"},
        %MyApp.Events.FundsDeposited{account_id: "account-1", amount: 500}
      ])
  """
  @spec for_event_source(t(), event_source_id(), [struct()]) :: t()
  def for_event_source(%__MODULE__{} = builder, event_source_id, events)
      when is_binary(event_source_id) and is_list(events) do
    entries =
      Enum.map(events, fn event ->
        event_type = event.__struct__
        event_type_id = event_type.__chronicle_event_type__(:id)
        tags = extract_tags(event)

        %{
          event_source_id: event_source_id,
          event_type_id: event_type_id,
          event: event,
          tags: tags,
          is_global: true,
          target_namespace: nil
        }
      end)

    %{builder | entries: builder.entries ++ entries}
  end

  @doc """
  Scopes subsequent events to a specific namespace.

  Returns a scoped builder that targets the given namespace.

  ## Parameters

    * `builder` — the seeding builder
    * `namespace` — the target namespace
    * `fun` — a function receiving a scoped builder

  ## Example

      builder
      |> Chronicle.Seeding.for_namespace("production", fn scoped ->
        scoped
        |> Chronicle.Seeding.for(MyEvent, "aggregate-1", [%MyEvent{...}])
      end)
  """
  @spec for_namespace(t(), namespace(), (t() -> t())) :: t()
  def for_namespace(%__MODULE__{} = builder, namespace, fun)
      when is_binary(namespace) and is_function(fun, 1) do
    scoped = %{builder | namespace: namespace}
    result = fun.(scoped)

    # Update entries to mark them as namespaced
    updated_entries =
      Enum.map(result.entries -- builder.entries, fn entry ->
        %{entry | is_global: false, target_namespace: namespace}
      end)

    %{builder | entries: builder.entries ++ updated_entries}
  end

  @doc """
  Registers all accumulated seed events with Chronicle.

  Organizes entries by global/namespaced, then by event type and event source,
  and sends them to the Chronicle server via gRPC.

  This is typically called automatically by `Chronicle.Client` during startup.
  """
  @spec register(t()) :: :ok | {:error, term()}
  def register(%__MODULE__{entries: entries} = _builder) when length(entries) == 0 do
    require Logger
    Logger.debug("No seed events to register")
    :ok
  end

  def register(%__MODULE__{} = builder) do
    require Logger

    global_entries = Enum.filter(builder.entries, & &1.is_global)
    namespaced_entries = Enum.reject(builder.entries, & &1.is_global)

    Logger.info(
      "Registering #{length(global_entries)} global seed events and #{length(namespaced_entries)} namespaced seed events"
    )

    builder
    |> group_entries_by_target()
    |> Enum.reduce_while(:ok, fn {{namespace, event_source_id}, entries}, :ok ->
      opts = [client: builder.client, namespace: namespace]

      case has_events_for(builder).(event_source_id, opts) do
        {:ok, true} ->
          Logger.debug(
            "Skipping seed data for #{event_source_id} in #{namespace}; events already exist"
          )

          {:cont, :ok}

        {:ok, false} ->
          case append_many(builder).(event_source_id, Enum.map(entries, & &1.event), opts) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Private helpers

  defp group_entries_by_target(%__MODULE__{} = builder) do
    builder.entries
    |> Enum.group_by(fn entry -> {target_namespace(entry, builder), entry.event_source_id} end)
    |> Enum.sort_by(fn {{namespace, event_source_id}, _entries} ->
      {namespace, event_source_id}
    end)
  end

  defp target_namespace(%{is_global: true}, %__MODULE__{namespace: namespace}), do: namespace

  defp target_namespace(%{target_namespace: namespace}, %__MODULE__{namespace: default_namespace}) do
    namespace || default_namespace
  end

  defp has_events_for(%__MODULE__{has_events_for: fun}) when is_function(fun, 2), do: fun
  defp has_events_for(_builder), do: &Chronicle.has_events_for?/2

  defp append_many(%__MODULE__{append_many: fun}) when is_function(fun, 3), do: fun
  defp append_many(_builder), do: &Chronicle.append_many/3

  defp extract_tags(%{__struct__: _module} = _event), do: []
end
