# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../../given/accounts.exs", __DIR__)
Code.require_file("../given/an_open_account.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForGiven.WhenProjecting.WithGivenContexts do
  use Cratis.Chronicle.Testing.ReadModelScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types(),
    given: [Cratis.Chronicle.Testing.ForGiven.Given.AFundedAccount],
    setup: {__MODULE__, :prepare}

  alias Cratis.Chronicle.Testing.Given.Accounts.Account

  def prepare(_client), do: %{prepared: true}

  test "should have the balance of the composed contexts", %{scenario: scenario} do
    should_have_read_model(scenario, Account, "account-1", %{owner_name: "Ada", balance: 15})
  end

  test("should have run the setup function first", context, do: assert(context.prepared))
end
