# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ResumeTest do
  use Chronicle.ImportsFakeKernel, async: false

  setup %{opts: opts, kernel: kernel} do
    Agent.update(kernel, &%{&1 | max_chunk_events: 3})

    # A producer staged two chunks, then crashed.
    {:ok, session} = Imports.begin(opts)
    {:ok, _} = Imports.add(session, Enum.take(Kernel.events(8), 6))
    Agent.update(kernel, &%{&1 | chunk_requests: []})
    :ok
  end

  test "reattaching continues after the acknowledged chunks", %{opts: opts, kernel: kernel} do
    assert {:ok, session} = Imports.reattach(Kernel.import_id(), opts)
    assert session.events_acknowledged == 6
    assert session.chunks_sent == 2

    assert {:ok, session} = Imports.add(session, Enum.drop(Enum.to_list(Kernel.events(8)), 6))

    assert {:ok, %ImportResult{state: :completed, events_committed: 8}} =
             Imports.complete(session)

    assert [%Wire.AddImportChunkRequest{ChunkIndex: 2, FirstEventIndex: 6}] =
             Kernel.chunk_requests(kernel)

    assert %Wire.CompleteImportRequest{ExpectedChunks: 3, ExpectedEvents: 8} =
             Kernel.state(kernel).completed
  end

  test "import resumes from the whole source, skipping what the kernel holds", %{
    opts: opts,
    kernel: kernel
  } do
    assert {:ok, %ImportResult{events_committed: 8}} =
             Imports.import(Kernel.events(8), Keyword.put(opts, :resume, Kernel.import_id()))

    assert [%{ChunkIndex: 2, FirstEventIndex: 6, Events: events}] = Kernel.chunk_requests(kernel)
    assert Enum.map(events, & &1."EventSourceId") == ["source-6", "source-7"]
  end

  test "a chunk sent again is staged once", %{opts: opts, kernel: kernel} do
    {:ok, session} = Imports.reattach(Kernel.import_id(), opts)
    replay = %{session | chunks_sent: 1, events_sent: 3}

    assert {:ok, _} = Imports.add(replay, Enum.slice(Enum.to_list(Kernel.events(8)), 3, 3))
    {first, events, _} = Kernel.state(kernel).staged[1]

    assert {first, Enum.map(events, & &1."EventSourceId")} ==
             {3, ["source-3", "source-4", "source-5"]}
  end

  test "an import into another event sequence cannot be reattached here", %{opts: opts} do
    assert {:error, {:import_targets_other_event_sequence, _, "event-log"}} =
             Imports.reattach(Kernel.import_id(), Keyword.put(opts, :event_sequence_id, "other"))
  end
end
