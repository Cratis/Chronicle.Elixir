# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForEventScenario.WhenAppending.AndTheAccountIsAlreadyOpen do
  use Cratis.Chronicle.Testing.EventScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types()

  alias Cratis.Chronicle.Testing.Given.Accounts.AccountOpened

  setup_all %{scenario: scenario} do
    scenario =
      scenario
      |> given_events("account-1", %AccountOpened{owner_name: "Ada"})
      |> append("account-1", %AccountOpened{owner_name: "Ada"})

    %{scenario: scenario}
  end

  test "should be refused by the constraint", %{scenario: scenario} do
    should_have_constraint_violation(scenario, "scenario-account-opened-once")
  end

  test("should append nothing", %{scenario: scenario},
    do: should_not_have_appended_any_events(scenario)
  )

  test "should keep the first event at the tail", %{scenario: scenario} do
    should_have_tail_sequence_number(scenario, 0)
  end
end
