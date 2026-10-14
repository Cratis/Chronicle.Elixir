# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.MultipleEventTypesWithSameIdFound do
  @moduledoc """
  Raised when several event type modules represent the same generation of the same event type id.

  Each generation of an event type must be represented by exactly one module.
  """

  defexception [:message, :event_type_id, :generation, :modules]

  @impl true
  def exception(opts) do
    event_type_id = Keyword.fetch!(opts, :event_type_id)
    generation = Keyword.fetch!(opts, :generation)
    modules = Keyword.fetch!(opts, :modules)

    %__MODULE__{
      event_type_id: event_type_id,
      generation: generation,
      modules: modules,
      message:
        "Multiple modules represent generation #{generation} of event type '#{event_type_id}': " <>
          "#{Enum.map_join(modules, ", ", &inspect/1)}. Each generation of an event type must be " <>
          "represented by exactly one module."
    }
  end
end
