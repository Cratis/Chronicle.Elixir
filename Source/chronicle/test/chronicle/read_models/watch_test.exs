# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.WatchTest do
  use ExUnit.Case, async: true

  alias Chronicle.ReadModels

  describe "unwatch/1" do
    test "stops the watcher process" do
      watcher =
        spawn(fn ->
          receive do
            :never -> :ok
          end
        end)

      ref = Process.monitor(watcher)

      assert :ok = ReadModels.unwatch(watcher)

      assert_receive {:DOWN, ^ref, :process, ^watcher, :shutdown}
    end
  end
end
