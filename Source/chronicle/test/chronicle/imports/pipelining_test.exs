# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.PipeliningTest do
  use Chronicle.ImportsFakeKernel, async: false

  @tag kernel_config: [max_chunk_events: 1, chunk_delay: 15]
  test "keeps at most four chunks in flight", %{opts: opts, kernel: kernel} do
    assert {:ok, %ImportResult{events_committed: 20}} = Imports.import(Kernel.events(20), opts)
    assert Kernel.state(kernel).peak_in_flight == 4
  end

  @tag kernel_config: [max_chunk_events: 1, chunk_delay: 15]
  test "honors a lower in-flight limit", %{opts: opts, kernel: kernel} do
    assert {:ok, _} =
             Imports.import(Kernel.events(10), Keyword.put(opts, :max_chunks_in_flight, 2))

    assert Kernel.state(kernel).peak_in_flight == 2
  end

  @tag kernel_config: [max_chunk_events: 2, failures: %{{1, 1} => 14, {1, 2} => 4}]
  test "sends a chunk again after a connection failure", %{opts: opts, kernel: kernel} do
    assert {:ok, %ImportResult{state: :completed, events_committed: 6}} =
             Imports.import(Kernel.events(6), opts)

    assert Kernel.state(kernel).attempts[1] == 3
    assert kernel |> Kernel.state() |> Map.get(:staged) |> map_size() == 3
  end

  @tag kernel_config: [max_chunk_events: 2, failures: %{{0, 1} => 14, {0, 2} => 14}]
  test "gives up on a chunk after the attempts allowed", %{opts: opts, kernel: kernel} do
    assert {:error, %GRPC.RPCError{status: 14}} =
             Imports.import(Kernel.events(2), Keyword.put(opts, :max_chunk_attempts, 2))

    assert Kernel.state(kernel).completed == nil
  end

  @tag kernel_config: [max_chunk_events: 2, refusals: %{1 => "chunk is too large"}]
  test "a chunk the kernel refuses stops the import", %{opts: opts, kernel: kernel} do
    assert {:error, {:import_chunk_refused, 1, "chunk is too large"}} =
             Imports.import(Kernel.events(6), opts)

    assert Kernel.state(kernel).completed == nil
  end

  @tag kernel_config: [unimplemented: true]
  test "a kernel without imports says so", %{opts: opts} do
    assert {:error, :imports_not_supported} = Imports.import(Kernel.events(1), opts)
  end

  test "import_async runs the import under a task", %{opts: opts} do
    task = Imports.import_async(Kernel.events(3), opts)
    assert %Task{} = task
    assert {:ok, %ImportResult{events_committed: 3}} = Task.await(task)
  end
end
