# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ResultsAndProgressTest do
  use Chronicle.ImportsFakeKernel, async: false

  def odd(event), do: if(Jason.decode!(event."Content")["n"] in [1, 4], do: ["schema mismatch"])

  @tag kernel_config: [reject: &__MODULE__.odd/1]
  test "rejected events fail the import and are reported by index", %{opts: opts} do
    assert {:ok, %ImportResult{} = result} = Imports.import(Kernel.events(6), opts)

    refute ImportResult.success?(result)
    assert result.state == :failed
    assert result.events_committed == 0
    assert result.first_sequence_number == nil
    assert result.rejected_count == 2
    assert result.failure_reason == "2 events were rejected"

    assert result.rejections == [
             %ImportRejection{
               index: 1,
               event_type: "imported-event",
               reasons: ["schema mismatch"]
             },
             %ImportRejection{
               index: 4,
               event_type: "imported-event",
               reasons: ["schema mismatch"]
             }
           ]
  end

  @tag kernel_config: [reject: &__MODULE__.odd/1]
  test "skipping invalid events commits the rest", %{opts: opts, kernel: kernel} do
    assert {:ok, result} = Imports.import(Kernel.events(6), Keyword.put(opts, :on_invalid, :skip))
    assert Kernel.state(kernel).on_invalid == :Skip
    assert result.state == :completed
    assert result.events_committed == 4
    assert {result.first_sequence_number, result.last_sequence_number} == {10, 13}
    assert length(result.rejections) == 2
  end

  test "progress is delivered to a process until the import ends", %{opts: opts} do
    id = Kernel.import_id()
    assert {:ok, _} = Imports.import(Kernel.events(3), Keyword.put(opts, :progress, self()))

    assert_receive {:chronicle_import_progress, ^id, %ImportProgress{state: :staging}}

    assert_receive {:chronicle_import_progress, ^id,
                    %ImportProgress{state: :completed, events_committed: 3, events_received: 3}}
  end

  test "observe sends progress to another process", %{opts: opts} do
    id = Kernel.import_id()
    {:ok, session} = Imports.begin(opts)
    {:ok, session} = Imports.add(session, Kernel.events(2))
    {:ok, _} = Imports.complete(session)

    assert {:ok, observer} = Imports.observe(id, Keyword.put(opts, :to, self()))
    assert is_pid(observer)
    assert_receive {:chronicle_import_progress, ^id, %ImportProgress{state: :completed}}
  end

  test "get reads an import's state", %{opts: opts} do
    {:ok, session} = Imports.begin(opts)
    {:ok, _} = Imports.add(session, Kernel.events(2))

    assert {:ok, %ImportResult{state: :staging, events_staged: 0}} =
             Imports.get(Kernel.import_id(), opts)
  end

  test "abandoning commits nothing", %{opts: opts, kernel: kernel} do
    {:ok, session} = Imports.begin(opts)
    {:ok, session} = Imports.add(session, Kernel.events(2))
    assert {:ok, %ImportResult{state: :abandoned, events_committed: 0}} = Imports.abandon(session)
    assert Kernel.state(kernel).completed == nil
  end

  test "completing without waiting returns the state the kernel reports", %{opts: opts} do
    {:ok, session} = Imports.begin(Keyword.put(opts, :wait_for_commit, false))
    {:ok, session} = Imports.add(session, Kernel.events(2))
    assert {:ok, %ImportResult{import_id: id}} = Imports.complete(session)
    assert id == Kernel.import_id()
  end
end
