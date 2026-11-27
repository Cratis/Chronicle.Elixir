# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForEventScenario.WhenTheScenarioHasNotAppended do
  use Cratis.Chronicle.Testing.EventScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types()

  test "should say that nothing has been appended", %{scenario: scenario} do
    assert_raise ExUnit.AssertionError, ~r/has not appended anything/, fn ->
      should_be_successful(scenario)
    end
  end
end
