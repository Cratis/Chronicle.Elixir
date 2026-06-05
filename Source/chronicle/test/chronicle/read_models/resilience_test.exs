# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.ResilienceTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.ReadModels.Resilience

  defp not_connected_error do
    %GRPC.RPCError{
      status: 2,
      message:
        "Exception was thrown by handler. NotSupportedException: Reducer 'X' is not connected. " <>
          "Reducer read model retrieval requires an active connected client."
    }
  end

  describe "call/3 without a lifecycle" do
    test "returns the result on success without retrying" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:ok, :value}
      end

      assert Resilience.call(nil, fun, attempts: 5, delay: 1) == {:ok, :value}
      assert :counters.get(counter, 1) == 1
    end

    test "retries the transient not-connected error until it succeeds" do
      counter = :counters.new(1, [])

      fun = fn ->
        attempt = :counters.get(counter, 1) + 1
        :counters.add(counter, 1, 1)
        if attempt < 3, do: {:error, not_connected_error()}, else: {:ok, :value}
      end

      assert Resilience.call(nil, fun, attempts: 5, delay: 1) == {:ok, :value}
      assert :counters.get(counter, 1) == 3
    end

    test "gives up after the maximum number of attempts" do
      counter = :counters.new(1, [])
      error = not_connected_error()

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:error, error}
      end

      assert Resilience.call(nil, fun, attempts: 3, delay: 1) == {:error, error}
      assert :counters.get(counter, 1) == 3
    end

    test "does not retry an unrelated error" do
      counter = :counters.new(1, [])
      error = %GRPC.RPCError{status: 4, message: "Deadline Exceeded"}

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:error, error}
      end

      assert Resilience.call(nil, fun, attempts: 5, delay: 1) == {:error, error}
      assert :counters.get(counter, 1) == 1
    end
  end

  describe "call/3 with a lifecycle" do
    test "waits until the connection is registered before running the fun" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      test = self()

      task =
        Task.async(fn ->
          Resilience.call(
            lifecycle,
            fn ->
              send(test, :ran)
              {:ok, :value}
            end,
            attempts: 1,
            delay: 1,
            wait_timeout: 1_000
          )
        end)

      refute_receive :ran, 100

      Lifecycle.connected(lifecycle, "conn-1")
      Lifecycle.registered(lifecycle)

      assert_receive :ran, 1_000
      assert Task.await(task) == {:ok, :value}
    end
  end

  describe "reducer_not_connected?/1" do
    test "is true for the transient not-connected error" do
      assert Resilience.reducer_not_connected?(not_connected_error())
    end

    test "is false for an unrelated gRPC error" do
      refute Resilience.reducer_not_connected?(%GRPC.RPCError{status: 4, message: "Deadline Exceeded"})
    end

    test "is false for a non-gRPC error" do
      refute Resilience.reducer_not_connected?(:some_other_reason)
    end
  end
end
