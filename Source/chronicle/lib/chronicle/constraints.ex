# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Constraints do
  @moduledoc """
  Registers event constraints with a Chronicle event store.

  Constraints enforce invariants on the event log. The most common constraint
  is a **unique constraint** — ensuring that no two events of the same type
  share the same property value within the same event store.

  ## Registering a unique constraint

      alias Chronicle.Constraints

      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)
      Constraints.register(channel, "my-store", [
        %{
          name: "unique-email",
          type: :unique,
          event_type_id: "user-registered-v1",
          on: ["Email"]
        }
      ])

  Constraints are typically registered as part of event type registration
  during client startup via `Chronicle.Client`.
  """

  alias Cratis.Chronicle.Contracts.Events.Constraints.{
    Constraints,
    RegisterConstraintsRequest,
    Constraint,
    UniqueConstraintDefinition,
    UniqueConstraintEventDefinition,
    OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition
  }

  @doc """
  Registers a list of constraint definitions with Chronicle.

  Each constraint map supports:

    * `:name` — **(required)** a unique constraint name
    * `:type` — **(required)** `:unique` or `:unique_event_type`
    * `:event_type_id` — the event type ID string this constraint applies to
    * `:on` — list of property path strings to check for uniqueness

  Returns `:ok` or `{:error, reason}`.
  """
  @spec register(term(), String.t(), [map()]) :: :ok | {:error, term()}
  def register(_channel, _event_store, []), do: :ok

  def register(channel, event_store, constraints) when is_list(constraints) do
    definitions =
      Enum.map(constraints, &build_constraint/1)

    request = %RegisterConstraintsRequest{
      EventStore: event_store,
      Constraints: definitions
    }

    case Constraints.Stub.register(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds constraint definitions from model-bound event type attributes.

  Event types can declare:

    * `@unique` / `unique(...)`
    * `@remove_constraint` / `remove_constraint(...)`
  """
  @spec from_event_types([module()]) :: [map()]
  def from_event_types(event_types) when is_list(event_types) do
    removal_event_types =
      event_types
      |> Enum.flat_map(fn event_type ->
        event_type
        |> event_type_constraints()
        |> Map.get(:remove_constraint, [])
        |> Enum.map(&{normalize_constraint_name(&1), event_type})
      end)
      |> Map.new()

    event_types
    |> Enum.flat_map(fn event_type ->
      event_type
      |> event_type_constraints()
      |> Map.get(:unique, [])
      |> Enum.map(&normalize_unique_declaration(&1, event_type))
    end)
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, definitions} ->
      %{
        type: :unique,
        name: name,
        event_definitions:
          Enum.map(definitions, fn definition ->
            %{event_type: definition.event_type, on: definition.on}
          end)
      }
      |> with_removed_with_event_type(Map.get(removal_event_types, name))
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_constraint(%{type: :unique, name: name, event_type_id: event_type_id, on: properties}) do
    build_constraint(%{
      type: :unique,
      name: name,
      event_definitions: [%{event_type_id: event_type_id, on: properties}]
    })
  end

  defp build_constraint(%{type: :unique, name: name, event_definitions: event_definitions} = constraint) do
    built_constraint = %Constraint{
      Name: name,
      Type: :Unique,
      Definition: %OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition{
        Value0: %UniqueConstraintDefinition{
          EventDefinitions: Enum.map(event_definitions, &build_unique_event_definition/1),
          IgnoreCasing: false
        }
      }
    }

    maybe_put_removed_with(built_constraint, removed_with_event_type_id(constraint))
  end

  defp build_constraint(%{type: :unique, name: name, event_type: event_module} = constraint) do
    properties = Map.get(constraint, :on, [])
    event_type_id = event_module.__chronicle_event_type__(:id)

    build_constraint(%{constraint | type: :unique, event_type_id: event_type_id, on: properties, name: name})
  end

  defp build_unique_event_definition(%{event_type_id: event_type_id, on: properties}) do
    %UniqueConstraintEventDefinition{
      EventTypeId: event_type_id,
      Properties: List.wrap(properties)
    }
  end

  defp build_unique_event_definition(%{event_type: event_type, on: properties}) do
    %UniqueConstraintEventDefinition{
      EventTypeId: event_type.__chronicle_event_type__(:id),
      Properties: List.wrap(properties)
    }
  end

  defp event_type_constraints(event_type) do
    if function_exported?(event_type, :__chronicle_event_type__, 1) do
      case event_type.__chronicle_event_type__(:constraints) do
        constraints when is_map(constraints) -> constraints
        _ -> %{}
      end
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp normalize_unique_declaration({fields, opts}, event_type) when is_list(opts) do
    normalized_fields = normalize_fields(fields)
    constraint_name = Keyword.get(opts, :name, default_constraint_name_for_fields(event_type, normalized_fields))
    build_normalized_unique(constraint_name, event_type, normalized_fields)
  end

  defp normalize_unique_declaration(opts, event_type) when is_list(opts) do
    fields = Keyword.get(opts, :on, Keyword.get(opts, :field, []))
    normalized_fields = normalize_fields(fields)
    constraint_name = Keyword.get(opts, :name, default_constraint_name_for_fields(event_type, normalized_fields))
    build_normalized_unique(constraint_name, event_type, normalized_fields)
  end

  defp normalize_unique_declaration(fields, event_type) do
    normalized_fields = normalize_fields(fields)
    build_normalized_unique(default_constraint_name_for_fields(event_type, normalized_fields), event_type, normalized_fields)
  end

  defp normalize_fields(fields) when is_list(fields), do: Enum.map(fields, &to_string/1)
  defp normalize_fields(field), do: [to_string(field)]

  defp normalize_constraint_name(name) when is_binary(name), do: name
  defp normalize_constraint_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_constraint_name(name), do: to_string(name)

  defp default_constraint_name_for_fields(_event_type, [field | _]), do: field

  defp default_constraint_name_for_fields(event_type, []) do
    if function_exported?(event_type, :__chronicle_event_type__, 1) do
      "#{event_type.__chronicle_event_type__(:id)}-constraint"
    else
      "#{event_type}-constraint"
    end
  end

  defp build_normalized_unique(name, event_type, normalized_fields) do
    %{name: normalize_constraint_name(name), event_type: event_type, on: normalized_fields}
  end

  defp with_removed_with_event_type(definition, nil), do: definition

  defp with_removed_with_event_type(definition, event_type) do
    Map.put(definition, :removed_with_event_type, event_type)
  end

  defp removed_with_event_type_id(%{removed_with_event_type: event_type}) when not is_nil(event_type) do
    event_type.__chronicle_event_type__(:id)
  end

  defp removed_with_event_type_id(_), do: ""

  defp maybe_put_removed_with(constraint, ""), do: constraint

  defp maybe_put_removed_with(constraint, removed_with) do
    if Map.has_key?(constraint, :RemovedWith) do
      Map.put(constraint, :RemovedWith, removed_with)
    else
      constraint
    end
  end
end
