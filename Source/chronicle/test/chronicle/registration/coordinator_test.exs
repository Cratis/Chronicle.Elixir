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
end
