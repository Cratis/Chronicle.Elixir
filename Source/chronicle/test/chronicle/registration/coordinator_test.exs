# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.CoordinatorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Registration.Coordinator

  setup do
    {:ok, lifecycle} = Lifecycle.start_link([])
    # Observe the lifecycle ourselves so we can assert on phase broadcasts.
    Lifecycle.subscribe(lifecycle)
    %{lifecycle: lifecycle}
  end

  defp start_coordinator(lifecycle, register_fun) do
    {:ok, pid} =
      Coordinator.start_link(
        connection: :unused,
        event_store: "test",
        lifecycle: lifecycle,
        register_fun: register_fun
      )

    pid
  end

  test "registers base artifacts on :connected then advances to :registered", %{
    lifecycle: lifecycle
  } do
    test = self()

    start_coordinator(lifecycle, fn _state ->
      send(test, :registered_called)
      :ok
    end)

    Lifecycle.connected(lifecycle, "conn-1")

    assert_receive :registered_called, 1_000
    assert_receive {:chronicle_lifecycle, :registered, "conn-1"}, 1_000
  end

  test "does not advance to :registered when registration fails", %{lifecycle: lifecycle} do
    test = self()

    start_coordinator(lifecycle, fn _state ->
      send(test, :registered_called)
      {:error, :boom}
    end)

    Lifecycle.connected(lifecycle, "conn-1")

    assert_receive :registered_called, 1_000
    refute_receive {:chronicle_lifecycle, :registered, _}, 200
    assert Lifecycle.phase(lifecycle) == :connected
  end

  test "re-runs registration on the next :connected after a disconnect", %{lifecycle: lifecycle} do
    test = self()

    start_coordinator(lifecycle, fn _state ->
      send(test, :registered_called)
      :ok
    end)

    Lifecycle.connected(lifecycle, "conn-1")
    assert_receive :registered_called, 1_000

    Lifecycle.disconnected(lifecycle)
    Lifecycle.connected(lifecycle, "conn-2")

    assert_receive :registered_called, 1_000
    assert_receive {:chronicle_lifecycle, :registered, "conn-2"}, 1_000
  end

  describe "status and awaiting" do
    test "reports registered and releases waiters", %{lifecycle: lifecycle} do
      pid = start_coordinator(lifecycle, fn _ -> :ok end)
      task = Task.async(fn -> Coordinator.await(pid, 2_000) end)

      Lifecycle.connected(lifecycle, "conn-1")

      assert Task.await(task) == :ok
      assert %{state: :registered, attempts: 0, error: nil} = Coordinator.status(pid)
      assert Coordinator.await(pid, 100) == :ok
    end

    test "a rejection that cannot succeed fails for good without retrying", %{
      lifecycle: lifecycle
    } do
      test = self()

      pid =
        start_coordinator(lifecycle, fn _ ->
          send(test, :attempt)
          {:error, {:validation_results, [:bad]}}
        end)

      Lifecycle.connected(lifecycle, "conn-1")

      assert_receive :attempt, 1_000
      refute_receive :attempt, 200

      assert {:error,
              {:failed, %{state: :failed, attempts: 1, error: {:validation_results, [:bad]}}}} =
               Coordinator.await(pid, 1_000)
    end

    test "gives up after max_attempts with the configured backoff", %{lifecycle: lifecycle} do
      test = self()

      {:ok, pid} =
        Coordinator.start_link(
          connection: :unused,
          event_store: "test",
          lifecycle: lifecycle,
          registration: [initial_delay: 10, max_delay: 20, max_attempts: 3],
          register_fun: fn _ ->
            send(test, :attempt)
            {:error, :down}
          end
        )

      Lifecycle.connected(lifecycle, "conn-1")

      assert {:error, {:failed, %{attempts: 3, error: :down}}} = Coordinator.await(pid, 2_000)
      assert_received :attempt
      assert Coordinator.status(pid).state == :failed
    end

    test "awaiting times out while registration is still being retried", %{lifecycle: lifecycle} do
      pid = start_coordinator(lifecycle, fn _ -> {:error, :down} end)
      Lifecycle.connected(lifecycle, "conn-1")

      assert Coordinator.await(pid, 100) == {:error, :timeout}
      assert %{state: :registering, error: :down, next_retry_in: 5_000} = Coordinator.status(pid)
    end
  end

  describe "identity_drift/1" do
    test "is empty before any registration attempt" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      pid = start_coordinator(lifecycle, fn _ -> :ok end)

      assert Coordinator.identity_drift(pid) == []
    end
  end

  describe "apply_drift_policy/2" do
    @warning_finding %Chronicle.Discovery.Drift{
      kind: :reactor,
      id: "some-reactor",
      reason: :observer_missing_from_code,
      severity: :warning
    }

    @info_finding %Chronicle.Discovery.Drift{
      kind: :reducer,
      id: "some-reducer",
      reason: :observer_missing_from_code,
      severity: :info
    }

    test ":ignore and :warn never block, regardless of findings" do
      assert Coordinator.apply_drift_policy([@warning_finding], :ignore) == :ok
      assert Coordinator.apply_drift_policy([@warning_finding], :warn) == :ok
      assert Coordinator.apply_drift_policy([], :warn) == :ok
    end

    test ":fail blocks on a :warning-severity finding" do
      assert {:error, {:artifact_identity_drift, [@warning_finding]}} =
               Coordinator.apply_drift_policy([@warning_finding], :fail)
    end

    test ":fail never blocks on an :info-severity finding alone" do
      assert Coordinator.apply_drift_policy([@info_finding], :fail) == :ok
    end

    test ":fail with no findings is clean" do
      assert Coordinator.apply_drift_policy([], :fail) == :ok
    end
  end
end
