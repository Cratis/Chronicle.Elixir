# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ChunkingTest do
  use Chronicle.ImportsFakeKernel, async: false

  @tag kernel_config: [max_chunk_events: 3]
  test "cuts events into chunks no larger than the kernel's event limit", %{
    opts: opts,
    kernel: kernel
  } do
    assert {:ok, %ImportResult{state: :completed, events_committed: 10}} =
             Imports.import(Kernel.events(10), opts)

    chunks = Kernel.chunk_requests(kernel)
    assert Enum.map(chunks, &length(&1."Events")) == [3, 3, 3, 1]
    assert Enum.map(chunks, & &1."ChunkIndex") == [0, 1, 2, 3]
    assert Enum.map(chunks, & &1."FirstEventIndex") == [0, 3, 6, 9]

    assert %Wire.CompleteImportRequest{ExpectedChunks: 4, ExpectedEvents: 10} =
             Kernel.state(kernel).completed
  end

  @tag kernel_config: [max_chunk_bytes: 300]
  test "cuts events into chunks no larger than the kernel's byte limit", %{
    opts: opts,
    kernel: kernel
  } do
    assert {:ok, %ImportResult{events_committed: 7}} =
             Imports.import(Kernel.events(7, payload: String.duplicate("x", 100)), opts)

    sizes =
      kernel
      |> Kernel.chunk_requests()
      |> Enum.map(fn chunk -> Enum.map(chunk."Events", &Chronicle.Imports.Wire.size_of/1) end)

    assert length(sizes) > 1
    assert Enum.all?(sizes, &(Enum.sum(&1) <= 300))

    # A chunk is closed only when the next event would not fit.
    sizes
    |> Enum.zip(tl(sizes))
    |> Enum.each(fn {chunk, [next | _]} -> assert Enum.sum(chunk) + next > 300 end)
  end

  @tag kernel_config: [max_chunk_events: 50]
  test "a client chunk limit below the kernel's applies", %{opts: opts, kernel: kernel} do
    assert {:ok, _} =
             Imports.import(Kernel.events(5), Keyword.put(opts, :max_events_per_chunk, 2))

    assert kernel |> Kernel.chunk_requests() |> Enum.map(&length(&1."Events")) == [2, 2, 1]
  end

  @tag kernel_config: [max_chunk_events: 2, chunk_delay: 20]
  test "reads the source lazily while uploading", %{opts: opts, kernel: kernel} do
    events =
      Kernel.events(8)
      |> Stream.each(fn entry ->
        Agent.update(kernel, &%{&1 | log: [{:read, entry.event.n} | &1.log]})
      end)

    assert {:ok, _} = Imports.import(events, Keyword.put(opts, :max_chunks_in_flight, 1))

    log = kernel |> Kernel.state() |> Map.get(:log) |> Enum.reverse()
    position = fn entry -> Enum.find_index(log, &(&1 == entry)) end

    # The last event is read only after the first chunk went out.
    assert position.({:chunk_sent, 0}) < position.({:read, 7})
  end

  test "an explicit session carries a partial chunk across adds", %{opts: opts, kernel: kernel} do
    Agent.update(kernel, &%{&1 | max_chunk_events: 3})
    entries = Enum.to_list(Kernel.events(4))

    assert {:ok, session} = Imports.begin(opts)
    assert session.import_id == Kernel.import_id()
    assert {:ok, session} = Imports.add(session, Enum.take(entries, 2))
    assert Kernel.chunk_requests(kernel) == []
    assert {:ok, session} = Imports.add(session, Enum.drop(entries, 2))
    assert {:ok, %ImportResult{state: :completed}} = Imports.complete(session)

    assert kernel |> Kernel.chunk_requests() |> Enum.map(&length(&1."Events")) == [3, 1]
  end

  test "an event sequence imports into itself", %{opts: opts} do
    sequence = Chronicle.EventSequences.EventSequence.new("inbox-copy")

    assert {:ok, _} =
             Chronicle.EventSequences.EventSequence.import(sequence, Kernel.events(1), opts)

    assert_received {:import_request, %Wire.BeginImportRequest{EventSequenceId: "inbox-copy"}}
  end

  test "an event of an unknown type stops the import before it is sent", %{
    opts: opts,
    kernel: kernel
  } do
    entry = %EventForEventSourceId{event_source_id: "s", event: %URI{}}
    assert {:error, {:unknown_event_type, URI}} = Imports.import([entry], opts)
    assert Kernel.chunk_requests(kernel) == []
    assert Kernel.state(kernel).completed == nil
  end
end
