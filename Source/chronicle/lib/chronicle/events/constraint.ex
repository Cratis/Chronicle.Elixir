# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.Constraint do
  @moduledoc """
  Macro for defining a standalone constraint module.

  Model-bound `unique/2`, `unique_event_type/1`, and `remove_constraint/1,2` attributes on an
  event type (see `Chronicle.Events.EventType`) cover the common case: a constraint that
  belongs to exactly one event type's own module. `use Chronicle.Events.Constraint` is for
  everything else — a constraint spanning several event types under one name, or one you want
  to define apart from any single event type's module. It mirrors the C# client's
  `IConstraint`/`IConstraintBuilder`.

  ## Defining a standalone constraint

      defmodule MyApp.Constraints.UniqueEmail do
        use Chronicle.Events.Constraint

        unique name: "UniqueEmail" do
          on MyApp.Events.UserRegistered, [:email]
          on MyApp.Events.UserEmailChanged, [:new_email]
          removed_with MyApp.Events.UserRemoved
        end
      end

  A unique event type constraint, with a releasing event declared afterward:

      defmodule MyApp.Constraints.OneOpenLoan do
        use Chronicle.Events.Constraint

        unique_event_type MyApp.Events.LoanCheckedOut, name: "OneOpenLoan"
        removed_with MyApp.Events.LoanReturned
      end

  Two `unique_event_type/1,2` declarations sharing a name become one constraint — mutual
  exclusion: at most one event drawn from the named set is ever appended for the same event
  source:

      defmodule MyApp.Constraints.PersonTerminalOutcome do
        use Chronicle.Events.Constraint

        unique_event_type MyApp.Events.PersonAliasedTo, name: "PersonTerminal"
        unique_event_type MyApp.Events.PersonErased, name: "PersonTerminal"
      end

  ## Registering

  Standalone constraint modules are discovered automatically (like event types and read
  models, through `:otp_app` or loaded-module discovery) or registered explicitly:

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        event_store: "my-store",
        constraints: [MyApp.Constraints.UniqueEmail]}

  ## `unique/2` options

    * `:name` — **(required)** the constraint name
    * `:mode` — `:per_event_source` (default) or `:per_value`; see
      `Chronicle.Events.EventType.unique/2`
    * `:ignore_casing` — compare values case-insensitively
    * `:message` — a string, or a `{Module, :function}` callback invoked with the violation to
      compute one; see `Chronicle.Events.ConstraintViolation.details/1`
    * `:scope` — see `Chronicle.Events.EventType.unique/2`
    * `:event_sequences` — restrict the declaration to specific event sequences (default: all)

  ## `on/2`

  Declares one of the event types (and the properties on it) that participate in the enclosing
  `unique/2` constraint. Call it more than once in the same block to constrain several event
  types under one name — the same event type cannot be added twice to one `unique/2` block.

  ## `removed_with/1,2`

  Inside a `unique/2 ... do ... end` block, declares a removal event. With `properties:`, the
  removal carries the value to release in `:per_value` mode, in the same order as the
  constrained properties; omitted or empty releases every value for the event source. After a
  bare `unique_event_type/1,2`, releases that constraint — there is no `properties:`, since a
  unique event type constraint has no constrained value. Calling it before any
  `unique_event_type/1,2` has been declared in the module is a compile-time error.

  ## `unique_event_type/1,2` options

    * `:name` — **(required)** the constraint name
    * `:message` — see above
    * `:scope` — see above
    * `:event_sequences` — see above
  """

  @doc """
  Returns metadata for a standalone constraint module. Accepts `:definitions`, the list of
  constraint definition maps this module declared, in the same shape
  `Chronicle.Events.Constraints.from_event_types/1` produces per constraint.
  """
  @callback __chronicle_constraint__(:definitions) :: [map()]

  @valid_unique_opts [:name, :mode, :ignore_casing, :message, :scope, :event_sequences]
  @valid_unique_event_type_opts [:name, :message, :scope, :event_sequences]

  defmacro __using__(_opts) do
    quote do
      @behaviour Chronicle.Events.Constraint

      Module.register_attribute(__MODULE__, :chronicle_constraint_definitions, accumulate: false)
      @chronicle_constraint_definitions []

      import Chronicle.Events.Constraint,
        only: [
          unique: 2,
          unique_event_type: 1,
          unique_event_type: 2,
          on: 2,
          removed_with: 1,
          removed_with: 2
        ]

      @before_compile Chronicle.Events.Constraint
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @impl Chronicle.Events.Constraint
      def __chronicle_constraint__(:definitions) do
        Enum.map(@chronicle_constraint_definitions, &Chronicle.Events.Constraint.__resolve__/1)
      end
    end
  end

  @doc """
  Starts a unique constraint built from one or more `on/2` declarations inside the block.

  See the moduledoc for the supported options.
  """
  defmacro unique(opts, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :chronicle_constraint_building_on, [])
      Module.put_attribute(__MODULE__, :chronicle_constraint_building_removed_with, [])

      unquote(block)

      Chronicle.Events.Constraint.__finish_unique__!(
        __MODULE__,
        unquote(opts),
        Module.get_attribute(__MODULE__, :chronicle_constraint_building_on),
        Module.get_attribute(__MODULE__, :chronicle_constraint_building_removed_with)
      )

      Module.delete_attribute(__MODULE__, :chronicle_constraint_building_on)
      Module.delete_attribute(__MODULE__, :chronicle_constraint_building_removed_with)
    end
  end

  @doc """
  Declares one of the event types (and properties) participating in the enclosing `unique/2`
  constraint. Call it more than once to constrain several event types under one name.
  """
  defmacro on(event_type, properties) do
    quote bind_quoted: [event_type: event_type, properties: properties] do
      Chronicle.Events.Constraint.__on__!(__MODULE__, event_type, properties)
    end
  end

  @doc """
  Declares a removal event. Inside a `unique/2 ... do ... end` block, releases the value with
  optional `properties:`. After a bare `unique_event_type/1,2`, releases that constraint.
  """
  defmacro removed_with(event_type, opts \\ [])

  defmacro removed_with(event_type, opts) do
    quote bind_quoted: [event_type: event_type, opts: opts] do
      Chronicle.Events.Constraint.__removed_with__!(__MODULE__, event_type, opts)
    end
  end

  @doc """
  Declares a unique constraint for the whole event type.

  See the moduledoc for the supported options. Two declarations sharing a `:name` merge into
  one mutually-exclusive constraint.
  """
  defmacro unique_event_type(event_type, opts \\ [])

  defmacro unique_event_type(event_type, opts) do
    quote bind_quoted: [event_type: event_type, opts: opts] do
      Chronicle.Events.Constraint.__add_unique_event_type__!(__MODULE__, event_type, opts)
    end
  end

  @doc false
  def __on__!(module, event_type, properties) do
    case Module.get_attribute(module, :chronicle_constraint_building_on) do
      nil ->
        raise ArgumentError,
              "#{inspect(module)}: on/2 must be called inside a `unique ... do ... end` block"

      current ->
        properties = properties |> List.wrap() |> Enum.map(&to_string/1)

        if Enum.any?(current, fn {existing_event_type, _} -> existing_event_type == event_type end) do
          raise ArgumentError,
                "#{inspect(module)}: #{inspect(event_type)} was added to the same unique " <>
                  "constraint more than once"
        end

        validate_property!(module, event_type, properties)

        Module.put_attribute(
          module,
          :chronicle_constraint_building_on,
          current ++ [{event_type, properties}]
        )
    end
  end

  @doc false
  def __removed_with__!(module, event_type, opts) do
    case Module.get_attribute(module, :chronicle_constraint_building_on) do
      nil -> add_top_level_removed_with!(module, event_type)
      _on -> add_block_removed_with!(module, event_type, opts)
    end
  end

  @doc false
  def __finish_unique__!(module, opts, on, removed_with) do
    validate_opts!(module, opts, @valid_unique_opts, "unique")
    name = validate_name!(module, opts)

    if on == [] do
      raise ArgumentError, "#{inspect(module)}: unique #{inspect(name)} has no `on` declaration"
    end

    definition =
      %{
        type: :unique,
        name: name,
        ignore_casing: Keyword.get(opts, :ignore_casing, false),
        event_definitions:
          Enum.map(on, fn {event_type, properties} ->
            %{event_type: event_type, on: properties}
          end)
      }
      |> maybe_put(:mode, Keyword.get(opts, :mode))
      |> maybe_put(:message, Keyword.get(opts, :message))
      |> maybe_put_scope(Keyword.get(opts, :scope))
      |> maybe_put_event_sequences(Keyword.get(opts, :event_sequences))
      |> maybe_put_removed_with(removed_with)

    register_definition!(module, definition)
  end

  @doc false
  def __add_unique_event_type__!(module, event_type, opts) do
    validate_opts!(module, opts, @valid_unique_event_type_opts, "unique_event_type")
    name = validate_name!(module, opts)

    definition =
      %{type: :unique_event_type, name: name, event_types: [event_type]}
      |> maybe_put(:message, Keyword.get(opts, :message))
      |> maybe_put_scope(Keyword.get(opts, :scope))
      |> maybe_put_event_sequences(Keyword.get(opts, :event_sequences))

    register_definition!(module, definition)
  end

  @doc false
  # Resolves module references into event type ids. Deferred to this runtime call (rather than
  # resolved while the module is still accumulating definitions) so declaring a constraint never
  # depends on the compile order between a Constraint module and the event types it names.
  def __resolve__(%{type: :unique_event_type} = definition) do
    definition
    |> Map.put(
      :event_type_ids,
      Enum.map(definition.event_types, & &1.__chronicle_event_type__(:id))
    )
    |> Map.delete(:event_types)
  end

  def __resolve__(definition), do: definition

  defp add_block_removed_with!(module, event_type, opts) do
    current = Module.get_attribute(module, :chronicle_constraint_building_removed_with)
    properties = opts |> Keyword.get(:properties, []) |> List.wrap() |> Enum.map(&to_string/1)

    Module.put_attribute(
      module,
      :chronicle_constraint_building_removed_with,
      current ++ [{event_type, properties}]
    )
  end

  # Mirrors C#'s `IConstraintBuilder.RemovedWith<TRemovalEventType>()`: attaches to the most
  # recently declared `unique_event_type/1,2`, wherever among the module's definitions it is.
  defp add_top_level_removed_with!(module, event_type) do
    existing = Module.get_attribute(module, :chronicle_constraint_definitions) || []

    existing
    |> Enum.with_index()
    |> Enum.filter(fn {definition, _index} -> definition.type == :unique_event_type end)
    |> List.last()
    |> case do
      nil ->
        raise ArgumentError,
              "#{inspect(module)}: removed_with/1 releases the unique event type constraint " <>
                "it follows, and no unique_event_type/1,2 has been declared on #{inspect(module)}"

      {definition, index} ->
        updated =
          Map.update(definition, :removed_with_event_types, [event_type], fn types ->
            Enum.uniq(types ++ [event_type])
          end)

        Module.put_attribute(
          module,
          :chronicle_constraint_definitions,
          List.replace_at(existing, index, updated)
        )
    end
  end

  defp register_definition!(module, definition) do
    existing = Module.get_attribute(module, :chronicle_constraint_definitions) || []

    new_list =
      case Enum.find_index(existing, &(&1.name == definition.name)) do
        nil -> existing ++ [definition]
        index -> merge_or_raise!(module, existing, index, definition)
      end

    Module.put_attribute(module, :chronicle_constraint_definitions, new_list)
  end

  defp merge_or_raise!(module, existing, index, definition) do
    found = Enum.at(existing, index)

    if found.type == :unique_event_type and definition.type == :unique_event_type do
      List.replace_at(existing, index, merge_unique_event_type(found, definition))
    else
      if found.type == :unique and definition.type == :unique and
           Map.get(found, :mode) != Map.get(definition, :mode) do
        raise ArgumentError,
              "#{inspect(module)}: unique constraint #{inspect(definition.name)} declares " <>
                "conflicting retention modes"
      end

      raise ArgumentError,
            "#{inspect(module)}: constraint name #{inspect(definition.name)} is declared more " <>
              "than once"
    end
  end

  defp merge_unique_event_type(a, b) do
    %{
      type: :unique_event_type,
      name: a.name,
      event_types: Enum.uniq(a.event_types ++ b.event_types)
    }
    |> maybe_put(:message, a[:message] || b[:message])
    |> maybe_put_merged(:scope, a, b)
    |> maybe_put_merged(:event_sequences, a, b)
    |> maybe_put_merged(:removed_with_event_types, a, b)
  end

  defp maybe_put_merged(definition, key, a, b) do
    case Enum.uniq((a[key] || []) ++ (b[key] || [])) do
      [] -> definition
      merged -> Map.put(definition, key, merged)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_scope(map, nil), do: map
  defp maybe_put_scope(map, scope), do: Map.put(map, :scope, List.wrap(scope))

  defp maybe_put_event_sequences(map, nil), do: map

  defp maybe_put_event_sequences(map, event_sequences) do
    Map.put(map, :event_sequences, event_sequences |> List.wrap() |> Enum.map(&to_string/1))
  end

  defp maybe_put_removed_with(definition, []), do: definition

  defp maybe_put_removed_with(definition, removed_with) do
    definition
    |> Map.put(:removed_with_event_types, removed_with |> Enum.map(&elem(&1, 0)) |> Enum.uniq())
    |> maybe_put_removal_event_definitions(removed_with)
  end

  defp maybe_put_removal_event_definitions(definition, removed_with) do
    case Enum.filter(removed_with, fn {_event_type, properties} -> properties != [] end) do
      [] ->
        definition

      with_properties ->
        Map.put(
          definition,
          :removal_event_definitions,
          Enum.map(with_properties, fn {event_type, properties} ->
            %{event_type: event_type, on: properties}
          end)
        )
    end
  end

  defp validate_name!(module, opts) do
    case Keyword.get(opts, :name) do
      nil ->
        raise ArgumentError,
              "#{inspect(module)}: a constraint declared with `use Chronicle.Events.Constraint` " <>
                "requires an explicit :name"

      name ->
        to_string(name)
    end
  end

  defp validate_opts!(module, opts, allowed, context) do
    case Chronicle.Events.Constraints.validate_unique_opts(opts, allowed) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "#{inspect(module)}: #{context} #{reason}"
    end
  end

  defp validate_property!(module, event_type, properties) do
    Code.ensure_compiled!(event_type)

    if function_exported?(event_type, :__struct__, 0) do
      struct_keys = event_type.__struct__() |> Map.keys()

      Enum.each(properties, fn property ->
        key = property |> to_string() |> String.to_atom()

        unless key in struct_keys do
          raise ArgumentError,
                "#{inspect(module)}: #{inspect(property)} does not exist on #{inspect(event_type)}"
        end
      end)
    end
  end
end
