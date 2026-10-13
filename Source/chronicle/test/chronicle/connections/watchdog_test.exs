# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.WatchdogTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Watchdog

  test "a registered client is left alone however long it has been" do
    assert Watchdog.decide(:registered, 0, 1_000_000, 100) == :ok
  end

  test "a client that is not registered is reconnected only after the limit" do
    assert Watchdog.decide(:connected, 1_000, 1_099, 100) == :ok
    assert Watchdog.decide(:connected, 1_000, 1_100, 100) == :reconnect
    assert Watchdog.decide(:disconnected, 0, 500, 100) == :reconnect
  end
end
