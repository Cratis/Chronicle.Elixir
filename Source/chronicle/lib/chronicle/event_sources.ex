# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources do
  @moduledoc """
  Describes, validates and registers event source definitions
  (see `Chronicle.EventSources.EventSource`).

  Registration is called by `Chronicle.Registration.Coordinator` at startup next
  to event types. It is an upsert: definitions omitted from a later registration
  are retained by the kernel.
  """

  alias Chronicle.EventSources.{ConcurrencyDimensions, DuplicateEventSourceName}

  alias Chronicle.WireResult

  alias Cratis.Chronicle.Contracts.EventSources.{
    EventSources,
    EventStreamDefinition,
    RegisterEventSourcesRequest
  }

  alias Chronicle.EventSources.EventSourceDefinition, as: Definition

  @doc """
  Describes the given event source modules and rejects duplicate source names.

  Returns the definitions, or raises `Chronicle.EventSources.DuplicateEventSourceName`.
  """
  @spec describe!([module()]) :: [Definition.t()]
  def describe!(modules) when is_list(modules) do
    definitions =
      modules
      |> Enum.uniq()
      |> Enum.map(fn module ->
        Code.ensure_loaded(module)

        unless function_exported?(module, :__chronicle_event_source__, 1) do
          raise ArgumentError,
                "#{inspect(module)} is not an event source, `use Chronicle.EventSources.EventSource`"
        end

        module.__chronicle_event_source__(:definition)
      end)

    definitions
    |> Enum.group_by(& &1.name)
    |> Enum.find(fn {_name, group} -> length(group) > 1 end)
    |> case do
      nil ->
        definitions

      {name, group} ->
        raise DuplicateEventSourceName, name: name, modules: Enum.map(group, & &1.module)
    end
  end

  @doc """
  Registers event source modules with the event store.

  Returns `:ok` (also for an empty list, where nothing is sent) or `{:error, reason}`.
  """
  @spec register(term(), String.t(), [module()]) :: :ok | {:error, term()}
  def register(_channel, _event_store, []), do: :ok

  def register(channel, event_store, modules) do
    request =
      struct(RegisterEventSourcesRequest,
        EventStore: event_store,
        Sources: modules |> describe!() |> Enum.map(&to_contract/1)
      )

    case EventSources.Stub.register_event_sources(channel, request) do
      {:ok, envelope} ->
        with {:ok, _} <- WireResult.unwrap(envelope), do: :ok

      {:error, reason} ->
        {:error, {:event_source_registration_failed, reason}}
    end
  end

  @doc false
  def to_contract(%Definition{} = definition) do
    struct(Cratis.Chronicle.Contracts.EventSources.EventSourceDefinition,
      Name: definition.name,
      Description: definition.description,
      Owner: :Client,
      Concurrency: ConcurrencyDimensions.to_flags(definition.concurrency),
      Streams:
        Enum.map(definition.streams, fn stream ->
          struct(EventStreamDefinition,
            Name: stream.name,
            Description: stream.description,
            Concurrency: ConcurrencyDimensions.to_flags(stream.concurrency)
          )
        end)
    )
  end
end
