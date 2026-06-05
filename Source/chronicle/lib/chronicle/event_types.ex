# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventTypes do
  @moduledoc """
  Registers event types with a Chronicle event store.

  Called automatically by `Chronicle.Projections.Registrar` during startup.
  You can also call it directly to register event types at runtime.

  ## Example

      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)

      :ok =
        Chronicle.EventTypes.register(
          channel,
          "my-store",
          [MyApp.Events.AccountOpened],
          [MyApp.Migrations.AccountOpenedV2Migration]
        )
  """

  alias Chronicle.Events.Migrators

  alias Cratis.Chronicle.Contracts.Events.{
    EventTypes,
    RegisterEventTypesRequest,
    EventTypeRegistration,
    EventType,
    EventTypeGenerationDefinition,
    EventTypeMigrationDefinition
  }

  @unknown_generation_schema "{}"

  @doc """
  Registers event type modules and their migrations with Chronicle.

  Each event type module must `use Chronicle.EventType`. Chronicle groups all
  known generations of the same event type into a single registration, includes
  schemas for each known generation, and attaches any registered migrations.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec register(term(), String.t(), [module()], [module()]) :: :ok | {:error, term()}
  def register(channel, event_store, event_type_modules, migration_modules \\ [])

  def register(_channel, _event_store, [], _migration_modules), do: :ok

  def register(channel, event_store, event_type_modules, migration_modules)
      when is_list(event_type_modules) and is_list(migration_modules) do
    migrators = Migrators.new(migration_modules)

    registrations =
      event_type_modules
      |> Enum.uniq()
      |> Enum.group_by(& &1.__chronicle_event_type__(:id))
      |> Enum.map(fn {_event_type_id, modules} ->
        build_registration(modules, event_store, migrators)
      end)

    request =
      struct(RegisterEventTypesRequest,
        EventStore: event_store,
        Types: registrations,
        DisableValidation: false
      )

    case EventTypes.Stub.register(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_registration(modules, event_store, migrators) do
    sorted_modules = Enum.sort_by(modules, & &1.__chronicle_event_type__(:generation))
    latest_module = List.last(sorted_modules)
    event_type_id = latest_module.__chronicle_event_type__(:id)
    latest_generation = latest_module.__chronicle_event_type__(:generation)

    generation_definitions =
      sorted_modules
      |> Enum.map(fn module ->
        struct(EventTypeGenerationDefinition,
          Generation: module.__chronicle_event_type__(:generation),
          Schema: generate_schema(module)
        )
      end)
      |> append_unknown_generations(Migrators.generations_for(migrators, event_type_id))

    migration_definitions =
      migrators
      |> Migrators.for_event_type(event_type_id)
      |> Enum.map(fn migration_module ->
        definition = Migrators.definition_for(migration_module)

        struct(EventTypeMigrationDefinition,
          FromGeneration: definition.from_generation,
          ToGeneration: definition.to_generation,
          UpcastJmesPath: definition.upcast_jmes_path,
          DowncastJmesPath: definition.downcast_jmes_path
        )
      end)

    struct(EventTypeRegistration,
      Type:
        struct(EventType,
          Id: event_type_id,
          Generation: latest_generation
        ),
      Schema: generate_schema(latest_module),
      Generations: generation_definitions,
      Migrations: migration_definitions,
      EventStore: event_store
    )
  end

  defp append_unknown_generations(generation_definitions, generations) do
    generation_definitions ++
      Enum.flat_map(generations, fn generation ->
        case Enum.any?(generation_definitions, &generation_definition_matches?(&1, generation)) do
          true ->
            []

          false ->
            [
              struct(EventTypeGenerationDefinition,
                Generation: generation,
                Schema: @unknown_generation_schema
              )
            ]
        end
      end)
  end

  defp generation_definition_matches?(definition, generation) do
    case Map.get(definition, :Generation, Map.get(definition, :generation)) do
      ^generation -> true
      _ -> false
    end
  end

  defp generate_schema(module) do
    fields =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.to_list()
        |> Enum.reject(fn {k, _} -> k == :__struct__ end)
        |> Enum.map(fn {key, default_val} ->
          camel_key = key |> Atom.to_string() |> snake_to_camel()
          {camel_key, event_property_schema(default_val)}
        end)
        |> Map.new()
      else
        %{}
      end

    Jason.encode!(%{"type" => "object", "properties" => fields})
  end

  # Use "number" without format: typeFormats.IsKnown(nil) returns false, so
  # ConvertJsonValueFromUnknownFormat is called with type=Number, which calls
  # GetValue<double>() — the only path that works for JsonElement-backed JSON numbers.
  defp event_property_schema(v) when is_integer(v), do: %{"type" => "number"}
  defp event_property_schema(v) when is_float(v), do: %{"type" => "number"}
  defp event_property_schema(v) when is_boolean(v), do: %{"type" => "boolean"}
  defp event_property_schema(_), do: %{"type" => "string"}

  defp snake_to_camel(snake) do
    [head | tail] = String.split(snake, "_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end
end
