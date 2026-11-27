# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForReadModelScenario.WhenEventsAreReduced do
  use Cratis.Chronicle.Testing.ReadModelScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types(),
    reducers: [Cratis.Chronicle.Testing.Given.Accounts.BalanceReducer]

  alias Cratis.Chronicle.Testing.Given.Accounts.{
    AccountOpened,
    Balance,
    BalanceReducer,
    FundsDeposited
  }

  setup_all %{scenario: scenario} do
    scenario =
      given_events(scenario, "account-1", [
        %AccountOpened{owner_name: "Ada", initial_balance: 10},
        %FundsDeposited{amount: 5}
      ])

    %{scenario: scenario}
  end

  test "should have the reduced balance", %{scenario: scenario} do
    should_have_read_model(scenario, BalanceReducer, "account-1", %Balance{balance: 15})
  end

  test "should have nothing for another account", %{scenario: scenario} do
    should_not_have_read_model(scenario, BalanceReducer, "account-2")
  end
end
