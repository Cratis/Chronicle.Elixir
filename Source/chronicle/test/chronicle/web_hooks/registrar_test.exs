# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.RegistrarTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.WebHooks.Registrar

  defp start_registrar(lifecycle, register_fun) do
    {:ok, pid} =
      Registrar.start_link(client: :test, lifecycle: lifecycle, register_fun: register_fun)

    pid
  end

  test "registers on the :registered phase, not on :connected" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    start_registrar(lifecycle, fn ->
      send(test, :registered_called)
      :ok
    end)

    Lifecycle.connected(lifecycle, "conn-1")
    refute_receive :registered_called, 100

    Lifecycle.registered(lifecycle)
    assert_receive :registered_called, 1_000
  end

  test "re-registers on the next :registered after a disconnect" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    start_registrar(lifecycle, fn ->
      send(test, :registered_called)
      :ok
    end)

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    assert_receive :registered_called, 1_000

    Lifecycle.disconnected(lifecycle)
    Lifecycle.connected(lifecycle, "conn-2")
    Lifecycle.registered(lifecycle)
    assert_receive :registered_called, 1_000
  end

  test "stays alive when registration fails" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    registrar =
      start_registrar(lifecycle, fn ->
        send(test, :attempted)
        {:error, :boom}
      end)

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    assert_receive :attempted, 1_000
    assert Process.alive?(registrar)
  end
end
