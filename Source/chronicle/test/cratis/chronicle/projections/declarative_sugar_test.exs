# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Projections.DeclarativeSugarTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Registration.Coordinator

  defmodule EntryAdded do
    use Cratis.Chronicle.Events.EventType, id: "declarative-sugar-entry-added"
    defstruct entry_id: "", name: ""
  end

  defmodule EntryArchivedElsewhere do
    use Cratis.Chronicle.Events.EventType, id: "declarative-sugar-entry-archived-elsewhere"
    defstruct archived_entry_id: ""
  end

  defmodule DiscountRemoved do
    use Cratis.Chronicle.Events.EventType, id: "declarative-sugar-discount-removed"
    defstruct []
  end

  defmodule LedgerReadModel do
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct ledger_id: "", entries: [], discount_code: "discount"
  end

  defmodule LedgerProjection do
    use Cratis.Chronicle.Projections.Projection, model: LedgerReadModel

    children(:entries,
      from: EntryAdded,
      identified_by: :entry_id,
      key: :entry_id,
      set: [entry_id: :entry_id, name: :name]
    )

    removed_with_join(EntryArchivedElsewhere, key: :archived_entry_id)
    clear_with(DiscountRemoved, [:discount_code])
  end

  defp f(map, key), do: Map.fetch!(map, key)

  test "every macro new in #127 is importable and usable in a declarative projection" do
    assert [{EntryArchivedElsewhere, [key: :archived_entry_id]}] =
             LedgerProjection.__chronicle_projection__(:removed_with_join)

    assert {DiscountRemoved, [clear: [:discount_code]]} in LedgerProjection.__chronicle_projection__(
             :from
           )

    assert [{:entries, [identified_by: :entry_id], [{:from, EntryAdded, _opts}]}] =
             LedgerProjection.__chronicle_projection__(:children)
  end

  test "builds the same RemovedWithJoin and children shape as a model-bound read model" do
    definition = Coordinator.build_declarative_projection_definition(LedgerProjection)

    [removed_with_join] = f(definition, :RemovedWithJoin)
    assert f(f(removed_with_join, :Value), :Key) == "archivedEntryId"

    entries = definition |> f(:Children) |> Map.fetch!("entries")
    assert f(entries, :IdentifiedBy) == "entry_id"
  end

  test "a root join without :on is a CompileError in a declarative projection too" do
    assert_raise CompileError, ~r/Missing the on property expression/, fn ->
      Code.eval_string("""
      defmodule Cratis.Chronicle.Projections.DeclarativeSugarTest.MissingOn do
        use Cratis.Chronicle.Projections.Projection,
          model: Cratis.Chronicle.Projections.DeclarativeSugarTest.LedgerReadModel

        join(Cratis.Chronicle.Projections.DeclarativeSugarTest.EntryAdded, set: [name: :name])
      end
      """)
    end
  end
end
