# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.Children do
  @moduledoc """
  Declares a **child collection** of a read model: a list on the parent that grows, changes and
  shrinks as events arrive. Mirrors the .NET client's `[ChildrenFrom<T>]` / `ChildrenBuilder`.

  Available inside `use Chronicle.ReadModels.ReadModel` and `use Chronicle.Projections.Projection`.

      defmodule MyApp.ReadModels.Basket do
        use Chronicle.ReadModels.ReadModel, types: [items: {:list, MyApp.ReadModels.BasketItem}]

        defstruct basket_id: "", items: []

        from MyApp.Events.BasketCreated, set: [basket_id: :event_source_id]

        children :items, identified_by: :item_id do
          from MyApp.Events.ItemAdded,
            key: :item_id,
            parent_key: :event_source_id,
            set: [item_id: :item_id, name: :name, quantity: :quantity]

          from MyApp.Events.QuantityIncreased,
            key: :item_id,
            parent_key: :event_source_id,
            add: [quantity: :amount]

          removed_with MyApp.Events.ItemRemoved, key: :item_id, parent_key: :event_source_id
        end
      end

  `identified_by` names the property of a child that identifies it. Inside the block `from/2`,
  `join/2`, `removed_with/2`, `removed_with_join/2`, `clear_with/2`, `from_every/1` and a nested
  `children/3` take the same options as on the read model itself. `key` is the expression that
  identifies the child an event applies to and `parent_key` identifies the parent it belongs to
  (both default to the event source id).

  ## One-line form

  A child collection that only ever grows from a single event does not need a `do` block:

      children :entries, from: MyApp.Events.EntryAdded,
        identified_by: :entry_id,
        key: :entry_id,
        set: [entry_id: :entry_id, name: :name]

  This is sugar for a block with exactly one `from` statement built from the same options (minus
  `:from` and `:identified_by`, which the one-line form consumes itself).

  ## Join `on:` inside children

  Unlike a root `join/2`, a join inside a `children` block does not require `:on` — it defaults
  to the collection's `identified_by`, because a child is always joined by its own identifying
  property. Passing an `:on` that disagrees with `identified_by` is accepted but produces a
  compile-time warning rather than an error, since the kernel still joins by `identified_by`.
  """

  alias Chronicle.Projections.Validation

  @doc """
  Declares a child collection: either a one-line form (`children name, from: Event,
  identified_by: ...`) or a `do` block of `from`/`join`/`removed_with`/etc statements, with or
  without options such as `:identified_by`. See the module documentation.
  """
  defmacro children(name, do: block) do
    build_block(name, [], block, __CALLER__)
  end

  defmacro children(name, opts) do
    build_one_line(name, opts, __CALLER__)
  end

  defmacro children(name, opts, do: block) do
    build_block(name, opts, block, __CALLER__)
  end

  defp build_block(name, opts, block, env) do
    Validation.require_identified_by!(name, opts, env.module, env)
    declarations = block |> block_statements() |> Enum.map(&declaration(&1, env))

    quote do
      @chronicle_projection_children {unquote(name), unquote(opts), unquote(declarations)}
    end
  end

  defp build_one_line(name, opts, env) do
    Validation.require_identified_by!(name, opts, env.module, env)
    {from_event, from_opts} = Keyword.pop!(opts, :from)
    from_opts = Keyword.delete(from_opts, :identified_by)

    Validation.reject_duplicate_properties!(
      Macro.to_string(from_event),
      from_opts,
      env.module,
      env
    )

    identified_by = Keyword.fetch!(opts, :identified_by)

    quote do
      @chronicle_projection_children {unquote(name), [identified_by: unquote(identified_by)],
                                      [{:from, unquote(from_event), unquote(from_opts)}]}
    end
  end

  @allowed [:from, :join, :removed_with, :removed_with_join, :clear_with, :from_every, :children]

  defp block_statements({:__block__, _, statements}), do: statements
  defp block_statements(nil), do: []
  defp block_statements(statement), do: [statement]

  defp declaration({:from_every, _, [opts]}, env) do
    Validation.reject_duplicate_properties!("from_every", opts, env.module, env)
    quote do: {:from_every, unquote(opts)}
  end

  defp declaration({:children, _, [name, [do: block]]}, env),
    do: declaration({:children, [], [name, [], [do: block]]}, env)

  defp declaration({:children, _, [name, opts, [do: block]]}, env) do
    Validation.require_identified_by!(name, opts, env.module, env)
    nested = block |> block_statements() |> Enum.map(&declaration(&1, env))
    quote do: {:children, unquote(name), unquote(opts), unquote(nested)}
  end

  defp declaration({:clear_with, _, [event, fields]}, env),
    do: declaration({:clear_with, [], [event, fields, []]}, env)

  defp declaration({:clear_with, _, [event, fields, opts]}, env) do
    merged = Keyword.put(opts, :clear, fields)
    Validation.reject_duplicate_properties!(Macro.to_string(event), merged, env.module, env)
    quote do: {:from, unquote(event), unquote(merged)}
  end

  defp declaration({kind, _, [event]}, env)
       when kind in [:from, :removed_with, :removed_with_join] do
    declaration({kind, [], [event, []]}, env)
  end

  defp declaration({kind, _, [event, opts]}, env) when kind in @allowed do
    if kind in [:from, :join] do
      Validation.reject_duplicate_properties!(Macro.to_string(event), opts, env.module, env)
    end

    quote do: {unquote(kind), unquote(event), unquote(opts)}
  end

  defp declaration({kind, _, _} = statement, _env) do
    raise ArgumentError,
          "unsupported statement #{inspect(kind)} in a children block: #{Macro.to_string(statement)}; " <>
            "expected one of #{inspect(@allowed)}"
  end

  defp declaration(other, _env) do
    raise ArgumentError, "unsupported children block statement: #{Macro.to_string(other)}"
  end

  alias Chronicle.Registration.Coordinator

  alias Cratis.Chronicle.Contracts.Projections.{
    ChildrenDefinition,
    FromDefinition,
    FromEveryDefinition,
    JoinDefinition,
    KeyValuePair_EventType_FromDefinition,
    KeyValuePair_EventType_JoinDefinition,
    KeyValuePair_EventType_RemovedWithDefinition,
    KeyValuePair_EventType_RemovedWithJoinDefinition,
    RemovedWithDefinition,
    RemovedWithJoinDefinition
  }

  @doc false
  # Builds the `Children` map of a projection definition from the `{name, opts, declarations}`
  # entries the macro collected. `model_module` resolves the key expressions' error messages.
  @spec build_map([tuple()], module()) :: %{String.t() => struct()}
  def build_map(children, model_module) do
    Map.new(children, fn {name, opts, declarations} ->
      {to_string(name), build_definition(name, opts, declarations, model_module)}
    end)
  end

  defp build_definition(name, opts, declarations, model_module) do
    identified_by =
      case Keyword.fetch(opts, :identified_by) do
        {:ok, property} ->
          to_string(property)

        :error ->
          raise ArgumentError,
                "children #{inspect(name)} on #{inspect(model_module)} requires :identified_by " <>
                  "(the property of a child that identifies it)"
      end

    from = for {:from, event, o} <- declarations, do: from_entry(event, o, model_module)

    join =
      for {:join, event, o} <- declarations,
          do: join_entry(event, o, identified_by, model_module)

    removed_with =
      for {:removed_with, event, o} <- declarations,
          do: removed_with_entry(event, o, model_module)

    removed_with_join =
      for {:removed_with_join, event, o} <- declarations,
          do: removed_with_join_entry(event, o, model_module)

    nested = for {:children, n, o, d} <- declarations, do: {n, o, d}

    all =
      case for({:from_every, o} <- declarations, do: o) do
        [] ->
          nil

        every ->
          struct(FromEveryDefinition,
            Properties:
              every
              |> Enum.map(&Coordinator.build_properties/1)
              |> Enum.reduce(%{}, &Map.merge(&2, &1)),
            IncludeChildren: Enum.any?(every, &Keyword.get(&1, :include_children, false))
          )
      end

    struct(ChildrenDefinition,
      IdentifiedBy: identified_by,
      From: from,
      Join: join,
      RemovedWith: removed_with,
      RemovedWithJoin: removed_with_join,
      Children: build_map(nested, model_module),
      All: all
    )
  end

  defp from_entry(event, opts, model_module) do
    struct(KeyValuePair_EventType_FromDefinition,
      Key: Coordinator.proto_event_type(event),
      Value:
        struct(FromDefinition,
          Key: key(opts, model_module),
          Properties: Coordinator.build_properties(opts),
          ParentKey: parent_key(opts)
        )
    )
  end

  defp join_entry(event, opts, identified_by, model_module) do
    on =
      Validation.resolve_child_join_on(
        opts,
        identified_by,
        model_module,
        event.__chronicle_event_type__(:id)
      )

    struct(KeyValuePair_EventType_JoinDefinition,
      Key: Coordinator.proto_event_type(event),
      Value:
        struct(JoinDefinition,
          On: on,
          Key: key(opts, model_module),
          Properties: Coordinator.build_properties(opts)
        )
    )
  end

  defp removed_with_entry(event, opts, model_module) do
    struct(KeyValuePair_EventType_RemovedWithDefinition,
      Key: Coordinator.proto_event_type(event),
      Value:
        struct(RemovedWithDefinition,
          Key: key(opts, model_module),
          ParentKey: parent_key(opts)
        )
    )
  end

  defp removed_with_join_entry(event, opts, model_module) do
    struct(KeyValuePair_EventType_RemovedWithJoinDefinition,
      Key: Coordinator.proto_event_type(event),
      Value: struct(RemovedWithJoinDefinition, Key: key(opts, model_module))
    )
  end

  defp key(opts, model_module),
    do:
      opts
      |> Keyword.get(:key, :event_source_id)
      |> Coordinator.resolve_key_expression(model_module)

  # A parent key is an expression like a key, so an event property or :event_source_id works.
  defp parent_key(opts) do
    case Keyword.get(opts, :parent_key) do
      nil -> ""
      parent_key -> Coordinator.resolve_key_expression(parent_key)
    end
  end
end
