# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.ChildrenOrderingTest do
  use ExUnit.Case, async: true

  alias Chronicle.Projections.Children.Ordering
  alias Chronicle.Registration.Coordinator

  @ordering_definition Cratis.Chronicle.Contracts.Projections.ChildrenOrderingDefinition

  defmodule EntryAdded do
    use Chronicle.Events.EventType, id: "children-ordering-entry-added"
    defstruct entry_id: "", position: 0
  end

  defmodule Appended do
    use Chronicle.ReadModels.ReadModel
    defstruct entries: []

    children :entries, identified_by: :entry_id do
      from(EntryAdded, key: :entry_id, set: [entry_id: :entry_id])
    end
  end

  defmodule Prepended do
    use Chronicle.ReadModels.ReadModel
    defstruct entries: []

    children :entries, identified_by: :entry_id, prepend: true do
      from(EntryAdded, key: :entry_id, set: [entry_id: :entry_id])
    end
  end

  defmodule SortedOneLine do
    use Chronicle.ReadModels.ReadModel
    defstruct entries: []

    children(:entries,
      from: EntryAdded,
      identified_by: :entry_id,
      order_by: [desc: :position],
      key: :entry_id,
      set: [entry_id: :entry_id, position: :position]
    )
  end

  defp children_definition(module) do
    module
    |> Coordinator.build_projection_definition()
    |> Map.fetch!(:Children)
    |> Map.fetch!("entries")
  end

  test "a collection without ordering options leaves the definition unchanged" do
    assert Map.get(children_definition(Appended), :Ordering) == nil
  end

  test "ordering options are kept with the collection, not the one-line from" do
    assert [{:entries, children_opts, [{:from, EntryAdded, from_opts}]}] =
             SortedOneLine.__chronicle_read_model__(:children)

    assert children_opts == [identified_by: :entry_id, order_by: [desc: :position]]
    refute Keyword.has_key?(from_opts, :order_by)
  end

  test "the options read as the placement the .NET client sends" do
    assert Ordering.from_options([]) == nil
    assert Ordering.from_options(prepend: true) == :prepend
    assert Ordering.from_options(order_by: :position) == {:sorted, "position", :ascending}
    assert Ordering.from_options(order_by: [asc: :position]) == {:sorted, "position", :ascending}

    assert Ordering.from_options(order_by: [desc: :position]) ==
             {:sorted, "position", :descending}
  end

  test "the placement maps onto ChildrenOrderingDefinition fields" do
    assert Ordering.fields(:prepend) == [Placement: :Prepend, SortBy: "", Direction: :Ascending]

    assert Ordering.fields({:sorted, "position", :descending}) ==
             [Placement: :Sorted, SortBy: "position", Direction: :Descending]
  end

  if Code.ensure_loaded?(@ordering_definition) do
    test "a declared ordering is registered on the children definition" do
      assert %{Placement: :Prepend} = Map.fetch!(children_definition(Prepended), :Ordering)

      assert %{Placement: :Sorted, SortBy: "position", Direction: :Descending} =
               Map.fetch!(children_definition(SortedOneLine), :Ordering)
    end
  else
    test "a declared ordering is refused when the contracts cannot carry it" do
      assert_raise ArgumentError, ~r/no ChildrenOrderingDefinition/, fn ->
        children_definition(Prepended)
      end
    end
  end

  test "prepend and order_by together are a compile-time error" do
    assert_raise CompileError, ~r/either prepend: true or order_by/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Projections.ChildrenOrderingTest.Conflicting do
        use Chronicle.ReadModels.ReadModel
        defstruct entries: []

        children :entries, identified_by: :entry_id, prepend: true, order_by: :position do
          from(Chronicle.Projections.ChildrenOrderingTest.EntryAdded, key: :entry_id)
        end
      end
      """)
    end
  end

  test "a malformed order_by is a compile-time error" do
    assert_raise CompileError, ~r/order_by must be a child property/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Projections.ChildrenOrderingTest.Malformed do
        use Chronicle.ReadModels.ReadModel
        defstruct entries: []

        children :entries, identified_by: :entry_id, order_by: [sideways: :position] do
          from(Chronicle.Projections.ChildrenOrderingTest.EntryAdded, key: :entry_id)
        end
      end
      """)
    end
  end

  test "nested collections validate their ordering too" do
    assert_raise CompileError, ~r/children :lines: order_by must be/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Projections.ChildrenOrderingTest.NestedMalformed do
        use Chronicle.ReadModels.ReadModel
        defstruct entries: []

        children :entries, identified_by: :entry_id do
          children :lines, identified_by: :line_id, order_by: "position" do
            from(Chronicle.Projections.ChildrenOrderingTest.EntryAdded, key: :entry_id)
          end
        end
      end
      """)
    end
  end
end
