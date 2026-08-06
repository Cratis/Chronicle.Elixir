# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptions.Definition do
  @moduledoc """
  Represents an event store subscription definition registered with Chronicle.
  """

  alias Chronicle.EventStoreSubscriptions.EventType

  alias Cratis.Chronicle.Contracts.Observation.EventStoreSubscriptions.EventStoreSubscriptionDefinition

  alias Cratis.Chronicle.Contracts.Observation.EventStoreSubscriptions.EventType,
    as: ProtoEventType

  defstruct id: "", source_event_store: "", event_types: []

  @type t :: %__MODULE__{
          id: String.t(),
          source_event_store: String.t(),
          event_types: [EventType.t()]
        }

  @doc false
  @spec to_proto(t()) :: EventStoreSubscriptionDefinition.t()
  def to_proto(%__MODULE__{} = definition) do
    struct(EventStoreSubscriptionDefinition,
      Identifier: definition.id,
      SourceEventStore: definition.source_event_store,
      EventTypes: Enum.map(definition.event_types, &event_type_to_proto/1)
    )
  end

  @doc false
  @spec from_proto(map()) :: t()
  def from_proto(definition) do
    %__MODULE__{
      id: Map.get(definition, :Identifier, ""),
      source_event_store: Map.get(definition, :SourceEventStore, ""),
      event_types: Map.get(definition, :EventTypes, []) |> Enum.map(&event_type_from_proto/1)
    }
  end

  defp event_type_to_proto(%EventType{} = event_type) do
    struct(ProtoEventType,
      Id: event_type.id,
      Generation: event_type.generation,
      Tombstone: event_type.tombstone?
    )
  end

  defp event_type_from_proto(event_type) do
    %EventType{
      id: Map.get(event_type, :Id, ""),
      generation: Map.get(event_type, :Generation, 1),
      tombstone?: Map.get(event_type, :Tombstone, false)
    }
  end
end
