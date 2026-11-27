# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForReadModelScenario.WhenEventsAreProjected do
  use Cratis.Chronicle.Testing.ReadModelScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types()

  alias Cratis.Chronicle.Testing.Given.Accounts.{Account, AccountOpened, FundsDeposited}

  setup_all %{scenario: scenario} do
    scenario =
      given_events(scenario, "account-1", [
        %AccountOpened{owner_name: "Ada", initial_balance: 10},
        %FundsDeposited{amount: 5}
      ])

    %{scenario: scenario}
  end

  test "should have the owner", %{scenario: scenario} do
    should_have_read_model(scenario, Account, "account-1", %{owner_name: "Ada"})
  end

  test "should have the balance of everything deposited", %{scenario: scenario} do
    should_have_read_model(scenario, Account, "account-1", &(&1.balance == 15))
  end

  test "should have the whole read model", %{scenario: scenario} do
    should_have_read_model(scenario, Account, "account-1", %Account{
      owner_name: "Ada",
      balance: 15
    })
  end

  test "should not have a read model for another account", %{scenario: scenario} do
    should_not_have_read_model(scenario, Account, "account-2")
  end

  test "should say what differs when the read model does not match", %{scenario: scenario} do
    assert_raise ExUnit.AssertionError, ~r/to match/, fn ->
      should_have_read_model(scenario, Account, "account-1", %{owner_name: "Grace"})
    end
  end
end
