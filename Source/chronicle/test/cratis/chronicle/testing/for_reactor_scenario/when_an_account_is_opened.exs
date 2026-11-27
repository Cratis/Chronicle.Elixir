# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/accounts.exs", __DIR__)

defmodule Cratis.Chronicle.Testing.ForReactorScenario.WhenAnAccountIsOpened do
  use Cratis.Chronicle.Testing.ReactorScenario,
    event_types: Cratis.Chronicle.Testing.Given.Accounts.event_types(),
    reactors: [Cratis.Chronicle.Testing.Given.Accounts.WelcomeReactor]

  alias Cratis.Chronicle.Testing.Given.Accounts.{AccountOpened, WelcomeSent}

  setup_all %{scenario: scenario} do
    %{scenario: append(scenario, "account-1", %AccountOpened{owner_name: "Ada"})}
  end

  test "should append the welcome the reactor produced", %{scenario: scenario} do
    should_have_appended(scenario, WelcomeSent, event_source_id: "account-1")
  end

  test("should not fail", %{scenario: scenario}, do: should_not_have_observer_failures(scenario))
end
