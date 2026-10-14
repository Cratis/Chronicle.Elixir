# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.MultipleMigratorsForSameEventTypeGeneration do
  @moduledoc """
  Raised when more than one migration module defines the migration between the same pair of
  generations for an event type. Exactly one migrator may bridge a pair of generations.
  """

  defexception [:message, :event_type_id, :from_generation, :to_generation, :modules]

  @impl true
  def exception(opts) do
    event_type_id = Keyword.fetch!(opts, :event_type_id)
    from_generation = Keyword.fetch!(opts, :from_generation)
    to_generation = Keyword.fetch!(opts, :to_generation)
    modules = Keyword.fetch!(opts, :modules)

    %__MODULE__{
      event_type_id: event_type_id,
      from_generation: from_generation,
      to_generation: to_generation,
      modules: modules,
      message:
        "Multiple migrators define the migration from generation #{from_generation} to " <>
          "generation #{to_generation} of event type '#{event_type_id}': " <>
          "#{Enum.map_join(modules, ", ", &inspect/1)}. Exactly one migrator may bridge a pair " <>
          "of generations."
    }
  end
end
