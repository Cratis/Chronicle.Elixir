# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.Constraints do
  @moduledoc """
  Registers event constraints with a Chronicle event store.

  Constraints enforce invariants on the event log. The most common constraint
  is a **unique constraint** — ensuring that no two events of the same type
  share the same property value within the same event store.

  ## Registering a unique constraint

      alias Chronicle.Events.Constraints

      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)
      Constraints.register(channel, "my-store", [
        %{
          name: "unique-email",
          type: :unique,
          event_type_id: "user-registered-v1",
          on: ["Email"],
          message: "Email is already taken"
        }
      ])

  Constraints are typically registered as part of event type registration
  during client startup via `Chronicle.Client`.
  """

  alias Cratis.Chronicle.Contracts.Events.Constraints.{
    Constraints,
    RegisterConstraintsRequest,
    Constraint,
    ConstraintScope,
    UniqueConstraintDefinition,
    UniqueConstraintEventDefinition,
    UniqueEventTypeConstraintDefinition,
    OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition
  }

  @doc """
  Registers a list of constraint definitions with Chronicle.

  Each constraint map supports:

    * `:name` — **(required)** a unique constraint name
    * `:type` — **(required)** `:unique` or `:unique_event_type`
    * `:event_type_id` — the event type ID string this constraint applies to
    * `:on` — list of property path strings to check for uniqueness
    * `:message` — optional human-readable message to use when the constraint
      is violated. This is a **client-side-only** concern, matching every
      other Cratis client (C#, TypeScript, Kotlin): the Chronicle kernel's
      wire `Constraint` message has no field for it, so it is never sent as
      part of registration. It is resolved locally against the `Message` on
      a returned `ConstraintViolation` once append-time violation resolution
      is wired up.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec register(term(), String.t(), [map()]) :: :ok | {:error, term()}
  def register(_channel, _event_store, []), do: :ok

  def register(channel, event_store, constraints) when is_list(constraints) do
    definitions = constraints |> Enum.map(&build_constraint/1) |> Enum.map(&elem(&1, 0))

    request =
      struct(RegisterConstraintsRequest,
        EventStore: event_store,
        Constraints: definitions
      )

    case Constraints.Stub.register(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds constraint definitions from model-bound event type attributes.

  Event types can declare:

    * `@unique` / `unique(...)`
    * `@unique_event_type` / `unique_event_type(...)`
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

    unique_constraints =
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
          ignore_casing: Enum.any?(definitions, &Map.get(&1, :ignore_casing, false)),
          event_definitions:
            Enum.map(definitions, fn definition ->
              %{event_type: definition.event_type, on: definition.on}
            end)
        }
        |> maybe_put_message(Enum.find_value(definitions, "", &Map.get(&1, :message)))
        |> maybe_put_scope(definitions |> Enum.flat_map(&Map.get(&1, :scope, [])) |> Enum.uniq())
        |> with_removed_with_event_type(Map.get(removal_event_types, name))
      end)

    unique_event_type_constraints =
      event_types
      |> Enum.flat_map(fn event_type ->
        event_type
        |> event_type_constraints()
        |> Map.get(:unique_event_type, [])
        |> Enum.map(&normalize_unique_event_type_declaration(&1, event_type))
      end)
      |> Enum.map(fn constraint ->
        constraint
        |> Map.put(:type, :unique_event_type)
        |> with_removed_with_event_type(Map.get(removal_event_types, constraint.name))
      end)

    (unique_constraints ++ unique_event_type_constraints)
    |> Enum.sort_by(& &1.name)
  end

  @doc false
  # Builds the wire `Constraint` for a single constraint definition map.
  #
  # Returns `{constraint, message}` rather than a bare `%Constraint{}`. The
  # `message` (from a `:message` key on the input map, defaulting to `""`
  # when absent) is deliberately kept off the returned `%Constraint{}` —
  # the generated `Cratis.Chronicle.Contracts.Events.Constraints.Constraint`
  # struct has no field for it (confirmed against the kernel proto and every
  # other Cratis client: C#'s `ConstraintConverters.ToContract()` never sends
  # a message at registration time either). Returning it alongside the wire
  # struct is what keeps the caller-supplied message from being silently
  # discarded — it is what a later, append-time violation-resolution phase
  # (mirroring C#'s `Constraints.ResolveMessageFor`) will read.
  @spec build_constraint(map()) :: {Constraint.t(), String.t()}
  def build_constraint(
        %{
          type: :unique,
          name: name,
          event_type_id: event_type_id,
          on: properties
        } = constraint
      ) do
    build_constraint(%{
      type: :unique,
      name: name,
      event_definitions: [%{event_type_id: event_type_id, on: properties}],
      message: Map.get(constraint, :message, "")
    })
  end

  def build_constraint(
        %{type: :unique, name: name, event_definitions: event_definitions} = constraint
      ) do
    definition =
      struct(OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition,
        Value0:
          struct(UniqueConstraintDefinition,
            EventDefinitions: Enum.map(event_definitions, &build_unique_event_definition/1),
            IgnoreCasing: Map.get(constraint, :ignore_casing, false)
          )
      )

    wire_constraint =
      struct(Constraint,
        Name: name,
        Type: :Unique,
        RemovedWith: removed_with_event_type_id(constraint),
        Definition: definition,
        Scope: build_constraint_scope(Map.get(constraint, :scope, []))
      )

    {wire_constraint, Map.get(constraint, :message, "")}
  end

  def build_constraint(
        %{type: :unique_event_type, name: name, event_type_id: event_type_id} = constraint
      ) do
    definition =
      struct(OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition,
        Value1: struct(UniqueEventTypeConstraintDefinition, EventTypeId: event_type_id)
      )

    wire_constraint =
      struct(Constraint,
        Name: name,
        Type: :UniqueEventType,
        RemovedWith: removed_with_event_type_id(constraint),
        Definition: definition
      )

    {wire_constraint, Map.get(constraint, :message, "")}
  end

  def build_constraint(%{type: :unique, name: name, event_type: event_module} = constraint) do
    properties = Map.get(constraint, :on, [])
    event_type_id = event_module.__chronicle_event_type__(:id)

    # `Map.merge/2` (not the `%{constraint | ...}` update syntax) because
    # `constraint` does not already have `:event_type_id` — the update
    # syntax requires every updated key to pre-exist and raises `KeyError`
    # otherwise.
    build_constraint(
      Map.merge(constraint, %{
        type: :unique,
        event_type_id: event_type_id,
        on: properties,
        name: name,
        message: Map.get(constraint, :message, "")
      })
    )
  end

  defp build_unique_event_definition(%{event_type_id: event_type_id, on: properties}) do
    struct(UniqueConstraintEventDefinition,
      EventTypeId: event_type_id,
      Properties: List.wrap(properties)
    )
  end

  defp build_unique_event_definition(%{event_type: event_type, on: properties}) do
    struct(UniqueConstraintEventDefinition,
      EventTypeId: event_type.__chronicle_event_type__(:id),
      Properties: List.wrap(properties)
    )
  end

  # Mirrors C#'s IConstraintBuilder.PerEventSourceType()/PerEventStreamType()/
  # PerEventStreamId(): each dimension is a boolean flag, encoded on the wire
  # as the presence (vs. absence) of a sentinel string value on the matching
  # ConstraintScope field — the kernel narrows the uniqueness check to values
  # observed at append time along the scoped dimension(s), not to a specific
  # literal value declared here.
  defp build_constraint_scope(scope) when is_list(scope) and scope != [] do
    struct(ConstraintScope)
    |> maybe_put_scoped(:EventSourceType, :per_event_source_type in scope)
    |> maybe_put_scoped(:EventStreamType, :per_event_stream_type in scope)
    |> maybe_put_scoped(:EventStreamId, :per_event_stream_id in scope)
  end

  defp build_constraint_scope(_scope), do: nil

  defp maybe_put_scoped(struct, key, true), do: Map.put(struct, key, "_scoped_")
  defp maybe_put_scoped(struct, _key, false), do: struct

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

    constraint_name =
      Keyword.get(opts, :name, default_constraint_name_for_fields(event_type, normalized_fields))

    build_normalized_unique(
      constraint_name,
      event_type,
      normalized_fields,
      Keyword.get(opts, :ignore_casing, false),
      Keyword.get(opts, :message, ""),
      normalize_scope(Keyword.get(opts, :scope))
    )
  end

  defp normalize_unique_declaration(opts, event_type) when is_list(opts) do
    fields = Keyword.get(opts, :on, Keyword.get(opts, :field, []))
    normalized_fields = normalize_fields(fields)

    constraint_name =
      Keyword.get(opts, :name, default_constraint_name_for_fields(event_type, normalized_fields))

    build_normalized_unique(
      constraint_name,
      event_type,
      normalized_fields,
      Keyword.get(opts, :ignore_casing, false),
      Keyword.get(opts, :message, ""),
      normalize_scope(Keyword.get(opts, :scope))
    )
  end

  defp normalize_unique_declaration(fields, event_type) do
    normalized_fields = normalize_fields(fields)

    build_normalized_unique(
      default_constraint_name_for_fields(event_type, normalized_fields),
      event_type,
      normalized_fields,
      false,
      "",
      []
    )
  end

  # A :scope option may be a single atom (:per_event_source_type) or a list of
  # them, for the (uncommon but valid, mirroring C#'s IConstraintBuilder)
  # case of scoping along more than one dimension at once.
  defp normalize_scope(nil), do: []
  defp normalize_scope(scope) when is_atom(scope), do: [scope]
  defp normalize_scope(scope) when is_list(scope), do: scope

  defp normalize_unique_event_type_declaration(opts, event_type) when is_list(opts) do
    name =
      normalize_constraint_name(
        Keyword.get(opts, :name, event_type.__chronicle_event_type__(:id))
      )

    %{name: name, event_type_id: event_type.__chronicle_event_type__(:id)}
    |> maybe_put_message(Keyword.get(opts, :message, ""))
  end

  defp normalize_unique_event_type_declaration(_opts, event_type) do
    name = normalize_constraint_name(event_type.__chronicle_event_type__(:id))
    %{name: name, event_type_id: event_type.__chronicle_event_type__(:id)}
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

  defp build_normalized_unique(name, event_type, normalized_fields, ignore_casing, message, scope) do
    %{
      name: normalize_constraint_name(name),
      event_type: event_type,
      on: normalized_fields,
      ignore_casing: ignore_casing
    }
    |> maybe_put_message(message)
    |> maybe_put_scope(scope)
  end

  # Only sets `:message` when a non-empty message was actually declared, so
  # constraint definition maps without a custom message keep their existing
  # (message-less) shape — matching every other Cratis client, where an
  # unset message resolves to an empty string rather than a present-but-empty
  # field.
  defp maybe_put_message(map, message) when is_binary(message) and message != "" do
    Map.put(map, :message, message)
  end

  defp maybe_put_message(map, _message), do: map

  defp maybe_put_scope(map, scope) when is_list(scope) and scope != [] do
    Map.put(map, :scope, scope)
  end

  defp maybe_put_scope(map, _scope), do: map

  defp with_removed_with_event_type(definition, nil), do: definition

  defp with_removed_with_event_type(definition, event_type) do
    Map.put(definition, :removed_with_event_type, event_type)
  end

  defp removed_with_event_type_id(%{removed_with_event_type: event_type})
       when not is_nil(event_type) do
    event_type.__chronicle_event_type__(:id)
  end

  defp removed_with_event_type_id(_), do: ""
end
