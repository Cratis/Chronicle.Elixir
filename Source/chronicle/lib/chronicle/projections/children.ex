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
  `join/2`, `removed_with/2`, `from_every/1` and a nested `children/3` take the same options as
  on the read model itself. `key` is the expression that identifies the child an event applies to
  and `parent_key` identifies the parent it belongs to (both default to the event source id).
  """

  @doc """
  Declares a child collection. See the module documentation.
  """
  defmacro children(name, opts \\ [], do: block) do
    declarations = block |> block_statements() |> Enum.map(&declaration/1)

    quote do
      @chronicle_projection_children {unquote(name), unquote(opts), unquote(declarations)}
    end
  end

  @allowed [:from, :join, :removed_with, :from_every, :children]

  defp block_statements({:__block__, _, statements}), do: statements
  defp block_statements(nil), do: []
  defp block_statements(statement), do: [statement]

  defp declaration({:from_every, _, [opts]}) do
    quote do: {:from_every, unquote(opts)}
  end

  defp declaration({:children, _, [name, [do: block]]}),
    do: declaration({:children, [], [name, [], [do: block]]})

  defp declaration({:children, _, [name, opts, [do: block]]}) do
    nested = block |> block_statements() |> Enum.map(&declaration/1)
    quote do: {:children, unquote(name), unquote(opts), unquote(nested)}
  end

  defp declaration({kind, _, [event]}) when kind in [:from, :removed_with] do
    quote do: {unquote(kind), unquote(event), []}
  end

  defp declaration({kind, _, [event, opts]}) when kind in @allowed do
    quote do: {unquote(kind), unquote(event), unquote(opts)}
  end

  defp declaration({kind, _, _} = statement) do
    raise ArgumentError,
          "unsupported statement #{inspect(kind)} in a children block: #{Macro.to_string(statement)}; " <>
            "expected one of #{inspect(@allowed)}"
  end

  defp declaration(other) do
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
    RemovedWithDefinition
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
    join = for {:join, event, o} <- declarations, do: join_entry(event, o, model_module)

    removed_with =
      for {:removed_with, event, o} <- declarations,
          do: removed_with_entry(event, o, model_module)

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

  defp join_entry(event, opts, model_module) do
    struct(KeyValuePair_EventType_JoinDefinition,
      Key: Coordinator.proto_event_type(event),
      Value:
        struct(JoinDefinition,
          On: opts |> Keyword.fetch!(:on) |> to_string(),
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
