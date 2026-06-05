# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.LifecycleTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle

  setup do
    {:ok, pid} = Lifecycle.start_link([])
    %{lifecycle: pid}
  end

  describe "subscribe/1" do
    test "returns the current phase snapshot", %{lifecycle: lc} do
      assert {:ok, :disconnected, connection_id} = Lifecycle.subscribe(lc)
      assert is_binary(connection_id)
    end

    test "delivers the current phase as a message", %{lifecycle: lc} do
      Lifecycle.subscribe(lc)
      assert_receive {:chronicle_lifecycle, :disconnected, _connection_id}
    end

    test "delivers the current phase to a late subscriber", %{lifecycle: lc} do
      Lifecycle.connected(lc, "abc123")
      assert {:ok, :connected, "abc123"} = Lifecycle.subscribe(lc)
      assert_receive {:chronicle_lifecycle, :connected, "abc123"}
    end
  end

  describe "phase transitions" do
    test "connected/2 adopts the id and broadcasts", %{lifecycle: lc} do
      Lifecycle.subscribe(lc)
      Lifecycle.connected(lc, "conn-1")

      assert_receive {:chronicle_lifecycle, :connected, "conn-1"}
      assert Lifecycle.phase(lc) == :connected
      assert Lifecycle.connection_id(lc) == "conn-1"
    end

    test "registered/1 broadcasts the registered phase", %{lifecycle: lc} do
      Lifecycle.subscribe(lc)
      Lifecycle.connected(lc, "conn-1")
      Lifecycle.registered(lc)

      assert_receive {:chronicle_lifecycle, :registered, "conn-1"}
      assert Lifecycle.phase(lc) == :registered
    end

    test "disconnected/1 broadcasts then rotates the connection id", %{lifecycle: lc} do
      Lifecycle.subscribe(lc)
      Lifecycle.connected(lc, "conn-1")
      assert_receive {:chronicle_lifecycle, :connected, "conn-1"}

      Lifecycle.disconnected(lc)
      # Broadcast carries the old id, then the id rotates.
      assert_receive {:chronicle_lifecycle, :disconnected, "conn-1"}
      assert Lifecycle.phase(lc) == :disconnected
      assert Lifecycle.connection_id(lc) != "conn-1"
    end

    test "connection id is stable across connected -> registered", %{lifecycle: lc} do
      Lifecycle.connected(lc, "conn-1")
      Lifecycle.registered(lc)
      assert Lifecycle.connection_id(lc) == "conn-1"
    end
  end

  describe "wait_until/3" do
    test "returns immediately when already at or beyond the target", %{lifecycle: lc} do
      Lifecycle.connected(lc, "conn-1")
      assert Lifecycle.wait_until(lc, :connected, 1_000) == :ok
    end

    test "blocks until the target phase is reached", %{lifecycle: lc} do
      task = Task.async(fn -> Lifecycle.wait_until(lc, :registered, 2_000) end)
      Process.sleep(50)
      Lifecycle.connected(lc, "conn-1")
      Lifecycle.registered(lc)
      assert Task.await(task) == :ok
    end

    test "times out when the target is not reached", %{lifecycle: lc} do
      assert Lifecycle.wait_until(lc, :registered, 100) == {:error, :timeout}
    end
  end

  describe "subscriber monitoring" do
    test "prunes a subscriber that exits without crashing the hub", %{lifecycle: lc} do
      pid = spawn(fn -> Lifecycle.subscribe(lc) end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      # The hub is still alive and functioning.
      Process.sleep(20)
      assert Process.alive?(lc)
      assert Lifecycle.phase(lc) == :disconnected
    end
  end
end
