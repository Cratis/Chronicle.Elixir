# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForEventScenario.WhenAppending.AndTheAccountIsNew do
  use Cratis.Chronicle.Testing.EventScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types()

  alias Cratis.Chronicle.Testing.Given.Accounts.{AccountOpened, FundsDeposited}

  setup_all %{scenario: scenario} do
    %{
      scenario:
        append(scenario, "account-1", [
          %AccountOpened{owner_name: "Ada"},
          %FundsDeposited{amount: 5}
        ])
    }
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test "should append both events, in order", %{scenario: scenario} do
    should_have_appended_exactly(scenario, [AccountOpened, %FundsDeposited{amount: 5}])
  end

  test "should append for that event source", %{scenario: scenario} do
    should_have_appended(scenario, AccountOpened, event_source_id: "account-1", count: 1)
  end

  test "should have the second event at the tail", %{scenario: scenario} do
    should_have_tail_sequence_number(scenario, 1)
  end
end
