# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.ChildrenTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  defmodule BasketCreated do
    use Chronicle.Events.EventType, id: "children-basket-created"
    defstruct []
  end

  defmodule ItemAdded do
    use Chronicle.Events.EventType, id: "children-item-added"
    defstruct item_id: "", name: "", quantity: 0
  end

  defmodule QuantityIncreased do
    use Chronicle.Events.EventType, id: "children-quantity-increased"
    defstruct item_id: "", amount: 0
  end

  defmodule ItemRemoved do
    use Chronicle.Events.EventType, id: "children-item-removed"
    defstruct item_id: ""
  end

  defmodule NoteAdded do
    use Chronicle.Events.EventType, id: "children-note-added"
    defstruct item_id: "", text: ""
  end

  defmodule Basket do
    use Chronicle.ReadModels.ReadModel

    defstruct basket_id: "", items: []

    from(BasketCreated, set: [basket_id: :event_source_id])

    children :items, identified_by: :item_id do
      from(ItemAdded,
        key: :item_id,
        parent_key: :event_source_id,
        set: [item_id: :item_id, name: :name, quantity: :quantity]
      )

      from(QuantityIncreased,
        key: :item_id,
        parent_key: :event_source_id,
        add: [quantity: :amount]
      )

      removed_with(ItemRemoved, key: :item_id, parent_key: :event_source_id)

      children :notes, identified_by: :note_id do
        from(NoteAdded, key: :item_id, set: [text: :text])
      end
    end
  end

  defp f(map, key), do: Map.fetch!(map, key)

  test "the declaration is collected" do
    assert [{:items, [identified_by: :item_id], declarations}] =
             Basket.__chronicle_read_model__(:children)

    assert Enum.map(declarations, &elem(&1, 0)) == [:from, :from, :removed_with, :children]
  end

  test "the projection definition carries the child collection" do
    definition = Coordinator.build_projection_definition(Basket)
    children = f(definition, :Children)

    assert Map.keys(children) == ["items"]
    items = children["items"]
    assert f(items, :IdentifiedBy) == "item_id"
    assert length(f(items, :From)) == 2
    assert length(f(items, :RemovedWith)) == 1

    [added | _] = f(items, :From)
    value = f(added, :Value)
    assert f(value, :Key) == "itemId"
    assert f(value, :ParentKey) == "$eventSourceId"
    assert f(value, :Properties)["quantity"] == "quantity"

    [_, increased] = f(items, :From)
    assert f(f(increased, :Value), :Properties) == %{"quantity" => "$add(amount)"}
  end

  test "children nest" do
    items = Coordinator.build_projection_definition(Basket) |> f(:Children) |> Map.fetch!("items")
    notes = items |> f(:Children) |> Map.fetch!("notes")
    assert f(notes, :IdentifiedBy) == "note_id"
    assert length(f(notes, :From)) == 1
  end

  test "identified_by is required" do
    assert_raise CompileError, ~r/requires :identified_by/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Projections.ChildrenTest.NoIdentity do
        use Chronicle.ReadModels.ReadModel
        defstruct items: []

        children :items do
          from(Chronicle.Projections.ChildrenTest.ItemAdded, set: [name: :name])
        end
      end
      """)
    end
  end

  test "an unsupported statement in the block is a compile-time error" do
    assert_raise ArgumentError, ~r/unsupported statement/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Projections.ChildrenTest.Bad do
        use Chronicle.ReadModels.ReadModel
        defstruct items: []

        children :items, identified_by: :id do
          bogus Foo
        end
      end
      """)
    end
  end

  test "clear maps a scalar back to no value" do
    assert Coordinator.build_properties(clear: [:nickname], set: [name: :name]) ==
             %{"nickname" => "$null", "name" => "name"}
  end
end
