# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForEventScenario.WhenAppending.AndAnotherAccountIsOpen do
  use Cratis.Chronicle.Testing.EventScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types()

  alias Cratis.Chronicle.Testing.Given.Accounts.AccountOpened

  setup_all %{scenario: scenario} do
    scenario =
      scenario
      |> given_events("account-1", %AccountOpened{owner_name: "Ada"})
      |> append("account-2", %AccountOpened{owner_name: "Grace"})

    %{scenario: scenario}
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test "should append only the new account", %{scenario: scenario} do
    should_have_appended_exactly(scenario, [%AccountOpened{owner_name: "Grace"}])
  end
end
