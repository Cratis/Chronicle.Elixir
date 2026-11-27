# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForReactorScenario.WhenAReactorFails do
  use Cratis.Chronicle.Testing.ReactorScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types(),
    reactors: [Cratis.Chronicle.Testing.Given.Accounts.FailingReactor]

  alias Cratis.Chronicle.Testing.Given.Accounts.{FailingReactor, FundsDeposited}

  setup_all %{scenario: scenario} do
    %{scenario: append(scenario, "account-1", %FundsDeposited{amount: 5})}
  end

  test "should have the failure of that reactor", %{scenario: scenario} do
    should_have_observer_failures(scenario, FailingReactor)
  end

  test "should have appended nothing but the event", %{scenario: scenario} do
    should_have_appended_exactly(scenario, [FundsDeposited])
  end
end
