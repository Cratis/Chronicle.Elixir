# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.ChildrenSugarTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  defmodule EntryAdded do
    use Chronicle.Events.EventType, id: "children-sugar-entry-added"
    defstruct entry_id: "", name: ""
  end

  defmodule EntryRemoved do
    use Chronicle.Events.EventType, id: "children-sugar-entry-removed"
    defstruct entry_id: ""
  end

  defmodule EntryArchivedElsewhere do
    use Chronicle.Events.EventType, id: "children-sugar-entry-archived-elsewhere"
    defstruct archived_entry_id: ""
  end

  defmodule EntryTagged do
    use Chronicle.Events.EventType, id: "children-sugar-entry-tagged"
    defstruct entry_id: "", tag: ""
  end

  defmodule DiscountRemoved do
    use Chronicle.Events.EventType, id: "children-sugar-discount-removed"
    defstruct []
  end

  defmodule OneLineLedger do
    use Chronicle.ReadModels.ReadModel

    defstruct ledger_id: "", entries: [], discount_code: "discount"

    children(:entries,
      from: EntryAdded,
      identified_by: :entry_id,
      key: :entry_id,
      set: [entry_id: :entry_id, name: :name]
    )

    clear_with(DiscountRemoved, [:discount_code])
  end

  defmodule RemovedWithJoinLedger do
    use Chronicle.ReadModels.ReadModel

    defstruct ledger_id: "", entries: []

    children :entries, identified_by: :entry_id do
      from(EntryAdded, key: :entry_id, set: [entry_id: :entry_id, name: :name])
      removed_with_join(EntryArchivedElsewhere, key: :archived_entry_id)
    end
  end

  defmodule ChildJoinDefaultOn do
    use Chronicle.ReadModels.ReadModel

    defstruct ledger_id: "", entries: []

    children :entries, identified_by: :entry_id do
      from(EntryAdded, key: :entry_id, set: [entry_id: :entry_id, name: :name])
      join(EntryTagged, key: :entry_id, set: [name: :tag])
    end
  end

  defp f(map, key), do: Map.fetch!(map, key)

  describe "one-line children" do
    test "builds a single from entry without a do block" do
      assert [
               {:entries, [identified_by: :entry_id],
                [
                  {:from, EntryAdded, [key: :entry_id, set: [entry_id: :entry_id, name: :name]]}
                ]}
             ] = OneLineLedger.__chronicle_read_model__(:children)
    end

    test "registers the same shape a block form would" do
      definition = Coordinator.build_projection_definition(OneLineLedger)
      entries = definition |> f(:Children) |> Map.fetch!("entries")

      assert f(entries, :IdentifiedBy) == "entry_id"
      assert length(f(entries, :From)) == 1
      [entry] = f(entries, :From)
      assert f(f(entry, :Value), :Key) == "entryId"
    end
  end

  describe "clear_with" do
    test "is sugar for from event, clear: [...]" do
      assert {DiscountRemoved, [clear: [:discount_code]]} in OneLineLedger.__chronicle_read_model__(
               :from
             )
    end

    test "produces a $null mapping in the projection definition" do
      definition = Coordinator.build_projection_definition(OneLineLedger)
      from_entries = f(definition, :From)

      clear_entry =
        Enum.find(from_entries, fn entry ->
          Map.get(f(entry, :Key), :Id) == DiscountRemoved.__chronicle_event_type__(:id)
        end)

      assert f(f(clear_entry, :Value), :Properties) == %{"discount_code" => "$null"}
    end
  end

  describe "removed_with_join" do
    test "is collected inside the children block, not at the root" do
      assert RemovedWithJoinLedger.__chronicle_read_model__(:removed_with_join) == []

      assert [{:entries, _opts, declarations}] =
               RemovedWithJoinLedger.__chronicle_read_model__(:children)

      assert {:removed_with_join, EntryArchivedElsewhere, [key: :archived_entry_id]} in declarations
    end

    test "builds a RemovedWithJoinDefinition inside the children definition" do
      definition = Coordinator.build_projection_definition(RemovedWithJoinLedger)
      entries = definition |> f(:Children) |> Map.fetch!("entries")

      assert length(f(entries, :RemovedWithJoin)) == 1
      [removed_with_join] = f(entries, :RemovedWithJoin)
      assert f(f(removed_with_join, :Value), :Key) == "archivedEntryId"
    end

    test "builds a RemovedWithJoinDefinition at the root of a projection definition" do
      definition = Coordinator.build_projection_definition(RemovedWithJoinLedger)

      # RemovedWithJoinLedger only declares removed_with_join inside children — the root
      # collection stays empty, proving it is not accidentally duplicated there.
      assert f(definition, :RemovedWithJoin) == []
    end
  end

  describe "child join on: default" do
    test "defaults on to identified_by when omitted" do
      definition = Coordinator.build_projection_definition(ChildJoinDefaultOn)
      entries = definition |> f(:Children) |> Map.fetch!("entries")

      [join] = f(entries, :Join)
      assert f(f(join, :Value), :On) == "entry_id"
    end

    test "warns, but does not raise, when an explicit on disagrees with identified_by" do
      defmodule WarnOnMismatch do
        use Chronicle.ReadModels.ReadModel
        defstruct ledger_id: "", entries: []

        children :entries, identified_by: :entry_id do
          from(EntryAdded, key: :entry_id, set: [entry_id: :entry_id, name: :name])
          join(EntryTagged, on: :tag, key: :entry_id, set: [name: :tag])
        end
      end

      warning =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Coordinator.build_projection_definition(WarnOnMismatch)
        end)

      assert warning =~ "differs from :identified_by"
    end
  end

  describe "compile-time validation" do
    test "a root join without :on is a CompileError naming the C# message" do
      assert_raise CompileError, ~r/Missing the on property expression/, fn ->
        Code.eval_string("""
        defmodule Chronicle.Projections.ChildrenSugarTest.MissingOn do
          use Chronicle.ReadModels.ReadModel
          defstruct ledger_id: "", tag: ""

          join(Chronicle.Projections.ChildrenSugarTest.EntryTagged, set: [tag: :tag])
        end
        """)
      end
    end

    test "a duplicate property target in one event mapping is a CompileError" do
      assert_raise CompileError, ~r/has already been defined/, fn ->
        Code.eval_string("""
        defmodule Chronicle.Projections.ChildrenSugarTest.DuplicateTarget do
          use Chronicle.ReadModels.ReadModel
          defstruct ledger_id: "", name: ""

          from(Chronicle.Projections.ChildrenSugarTest.EntryAdded,
            set: [name: :name],
            add: [name: :name]
          )
        end
        """)
      end
    end

    test "a from target that is not a struct field is a CompileError" do
      assert_raise CompileError, ~r/is not a field of its struct/, fn ->
        Code.eval_string("""
        defmodule Chronicle.Projections.ChildrenSugarTest.UnknownTarget do
          use Chronicle.ReadModels.ReadModel
          defstruct ledger_id: ""

          from(Chronicle.Projections.ChildrenSugarTest.EntryAdded,
            set: [not_a_field: :name]
          )
        end
        """)
      end
    end

    test "a children name that is not a struct field is a CompileError" do
      assert_raise CompileError, ~r/is not a field of its struct/, fn ->
        Code.eval_string("""
        defmodule Chronicle.Projections.ChildrenSugarTest.UnknownChildrenName do
          use Chronicle.ReadModels.ReadModel
          defstruct ledger_id: ""

          children :not_a_field, identified_by: :entry_id do
            from(Chronicle.Projections.ChildrenSugarTest.EntryAdded, set: [])
          end
        end
        """)
      end
    end
  end
end
