# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptions.DefinitionBuilder do
  @moduledoc """
  Immutable builder for event store subscription definitions.

  When no event types are configured explicitly, the builder uses all registered
  event types passed to `new/1`.
  """

  alias Chronicle.EventStoreSubscriptions.{Definition, EventType}

  defstruct registered_event_types: [], event_types: []

  @type t :: %__MODULE__{
          registered_event_types: [module()],
          event_types: [module()]
        }

  @doc """
  Creates a new definition builder.
  """
  @spec new([module()]) :: t()
  def new(registered_event_types \\ []) do
    %__MODULE__{registered_event_types: Enum.uniq(registered_event_types)}
  end

  @doc """
  Adds an event type to the subscription definition.
  """
  @spec with_event_type(t(), module()) :: t()
  def with_event_type(%__MODULE__{} = builder, event_type) when is_atom(event_type) do
    %{builder | event_types: Enum.uniq(builder.event_types ++ [event_type])}
  end

  @doc """
  Builds an event store subscription definition.
  """
  @spec build(t(), String.t(), String.t()) :: Definition.t()
  def build(%__MODULE__{} = builder, id, source_event_store)
      when is_binary(id) and is_binary(source_event_store) do
    if String.trim(id) == "" do
      raise ArgumentError, "event store subscription id cannot be empty"
    end

    if String.trim(source_event_store) == "" do
      raise ArgumentError, "event store subscription '#{id}' has an empty source event store"
    end

    event_type_modules =
      case builder.event_types do
        [] -> builder.registered_event_types
        modules -> modules
      end

    %Definition{
      id: id,
      source_event_store: source_event_store,
      event_types: Enum.map(event_type_modules, &event_type_from_module/1)
    }
  end

  defp event_type_from_module(module) do
    unless function_exported?(module, :__chronicle_event_type__, 1) do
      raise ArgumentError, "#{inspect(module)} is not a Chronicle event type"
    end

    id = module.__chronicle_event_type__(:id)

    if id in [nil, ""] do
      raise ArgumentError, "#{inspect(module)} has an invalid Chronicle event type id"
    end

    %EventType{
      id: id,
      generation: module.__chronicle_event_type__(:generation),
      tombstone?: false
    }
  end
end
