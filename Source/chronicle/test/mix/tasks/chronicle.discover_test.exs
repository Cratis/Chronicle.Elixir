# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Chronicle.DiscoverTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Chronicle.Discover

  describe "execute/1" do
    test "requires --otp-app" do
      assert {output, 2} = Discover.execute([])
      assert output =~ "--otp-app is required"
    end

    test "rejects an unrecognized option" do
      assert {output, 2} = Discover.execute(["--bogus"])
      assert output =~ "Unrecognized option"
    end

    test "prints the discovery report for an application with no modules, without connecting" do
      assert {output, 0} = Discover.execute(["--otp-app", "nonexistent_app"])
      assert output =~ "Chronicle discovery report:"
      assert output =~ "event types (0)"
    end

    test "reports a connection failure as exit code 2, without crashing" do
      assert {output, 2} =
               Discover.execute([
                 "--otp-app",
                 "nonexistent_app",
                 "--connection-string",
                 "chronicle://localhost:1"
               ])

      assert output =~ "Could not connect"
    end
  end
end
