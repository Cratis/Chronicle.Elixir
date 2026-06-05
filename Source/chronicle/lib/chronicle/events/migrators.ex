# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.Migrators do
  @moduledoc """
  Discovers, groups, and materializes event type migrations.

  `Chronicle.EventTypes` uses this module while registering event types so each
  event type registration includes its known generations and migration chain.
  """

  alias Chronicle.Events.MigrationBuilder

  @enforce_keys [:all, :by_event_type]
  defstruct all: [], by_event_type: %{}

  @type migration_module :: module()
  @type definition :: %{
          from_generation: pos_integer(),
          to_generation: pos_integer(),
          upcast_jmes_path: String.t(),
          downcast_jmes_path: String.t()
        }
  @type t :: %__MODULE__{
          all: [migration_module()],
          by_event_type: %{optional(String.t()) => [migration_module()]}
        }

  @doc """
  Creates a migrator registry from migration modules.
  """
  @spec new([migration_module()]) :: t()
  def new(migration_modules \\ []) when is_list(migration_modules) do
    modules =
      migration_modules
      |> Enum.uniq()
      |> Enum.sort_by(&sort_key/1)

    %__MODULE__{
      all: modules,
      by_event_type: Enum.group_by(modules, & &1.__chronicle_migration__(:event_type_id))
    }
  end

  @doc """
  Returns all registered migration modules.
  """
  @spec all(t()) :: [migration_module()]
  def all(%__MODULE__{all: all}), do: all

  @doc """
  Returns the migration modules for an event type module or event type id.
  """
  @spec for_event_type(t(), module() | String.t()) :: [migration_module()]
  def for_event_type(%__MODULE__{by_event_type: by_event_type}, event_type) do
    Map.get(by_event_type, event_type_id(event_type), [])
  end

  @doc """
  Returns all known generations for an event type.
  """
  @spec generations_for(t(), module() | String.t()) :: [pos_integer()]
  def generations_for(%__MODULE__{} = migrators, event_type) do
    migrators
    |> for_event_type(event_type)
    |> Enum.flat_map(fn migration_module ->
      [
        migration_module.__chronicle_migration__(:from_generation),
        migration_module.__chronicle_migration__(:to_generation)
      ]
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Builds the registration definition for a migration module.
  """
  @spec definition_for(migration_module()) :: definition()
  def definition_for(migration_module) do
    upcast_builder = migration_module.upcast(MigrationBuilder.new())
    downcast_builder = migration_module.downcast(MigrationBuilder.new())

    %{
      from_generation: migration_module.__chronicle_migration__(:from_generation),
      to_generation: migration_module.__chronicle_migration__(:to_generation),
      upcast_jmes_path: MigrationBuilder.to_json(upcast_builder),
      downcast_jmes_path: MigrationBuilder.to_json(downcast_builder)
    }
  end

  defp event_type_id(event_type) when is_binary(event_type), do: event_type
  defp event_type_id(event_type), do: event_type.__chronicle_event_type__(:id)

  defp sort_key(migration_module) do
    {
      migration_module.__chronicle_migration__(:event_type_id),
      migration_module.__chronicle_migration__(:from_generation),
      migration_module.__chronicle_migration__(:to_generation),
      inspect(migration_module)
    }
  end
end
