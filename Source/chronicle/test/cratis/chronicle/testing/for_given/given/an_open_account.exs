# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.ForGiven.Given.AnOpenAccount do
  use Cratis.Chronicle.Testing.Given

  alias Cratis.Chronicle.Testing.Given.Accounts.{AccountOpened, FundsDeposited}

  @impl true
  def given(scenario),
    do:
      given_events(scenario, "account-1", %AccountOpened{owner_name: "Ada", initial_balance: 10})

  @impl true
  def given(scenario, amount),
    do: given_events(scenario, "account-1", %FundsDeposited{amount: amount})
end

defmodule Cratis.Chronicle.Testing.ForGiven.Given.AFundedAccount do
  use Cratis.Chronicle.Testing.Given

  alias Cratis.Chronicle.Testing.ForGiven.Given.AnOpenAccount

  @impl true
  def given(scenario),
    do: scenario |> given_context(AnOpenAccount) |> given_context({AnOpenAccount, 5})
end
