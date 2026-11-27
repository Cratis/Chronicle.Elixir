# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.ReactorScenario do
  @moduledoc """
  A spec scenario for reactors: the Elixir counterpart of `ReactorScenario<TReactor>`.

  Events are appended; the registered reactors run (synchronously, as in `Cratis.Chronicle.Testing`),
  and the spec states what they did. A reactor's **observable effects** are what is asserted: the
  events it appended in turn, and whatever it called (an integration, usually a stand-in the spec reads).

      defmodule MyApp.Secrets.ForRetireSecret.WhenASecretIsRevoked do
        use Cratis.Chronicle.Testing.ReactorScenario,
          event_types: [MyApp.Secrets.SecretRevoked, MyApp.Secrets.SecretRetiredInOry],
          reactors: [MyApp.Secrets.RetireSecret]

        setup_all %{scenario: scenario} do
          %{scenario: append(scenario, "client-1", %MyApp.Secrets.SecretRevoked{})}
        end

        test "should record that the secret was retired", %{scenario: scenario} do
          should_have_appended(scenario, MyApp.Secrets.SecretRetiredInOry, event_source_id: "client-1")
        end

        test "should not fail", %{scenario: scenario}, do: should_not_have_observer_failures(scenario)
      end

  `use` is the one of `Cratis.Chronicle.Testing.EventScenario` (same options and lifecycle; pass
  `reactors:`), and this module has the same given, because and should functions, plus
  `should_have_observer_failures/1,2` for a reactor that is expected to fail.
  """

  alias Cratis.Chronicle.Testing.{EventScenario, Scenarios}

  defmacro __using__(opts), do: Scenarios.using(__MODULE__, opts)

  defdelegate new(client), to: EventScenario
  defdelegate given_events(scenario, event_source_id, events), to: EventScenario
  defdelegate append(scenario, event_source_id, events), to: EventScenario
  defdelegate append(scenario, event_source_id, events, opts), to: EventScenario
  defdelegate should_have_appended(scenario, matcher), to: EventScenario
  defdelegate should_have_appended(scenario, matcher, opts), to: EventScenario
  defdelegate should_not_have_appended(scenario, matcher), to: EventScenario
  defdelegate should_not_have_appended(scenario, matcher, opts), to: EventScenario
  defdelegate should_have_appended_exactly(scenario, matchers), to: EventScenario
  defdelegate should_not_have_appended_any_events(scenario), to: EventScenario
  defdelegate should_have_tail_sequence_number(scenario, expected), to: EventScenario
  defdelegate should_not_have_observer_failures(scenario), to: EventScenario

  @doc """
  A reactor or reducer should have failed. With a module, one whose failure names it; failures are
  `{:reactor | :reducer, module, reason}`.
  """
  @spec should_have_observer_failures(EventScenario.t(), module() | nil) :: EventScenario.t()
  def should_have_observer_failures(%EventScenario{failures: failures} = scenario, module \\ nil) do
    cond do
      failures == [] ->
        Scenarios.fail("Expected a reactor or reducer to fail, but none did")

      module == nil ->
        scenario

      Enum.any?(failures, &match?({_kind, ^module, _reason}, &1)) ->
        scenario

      true ->
        Scenarios.fail(
          "Expected #{inspect(module)} to fail, got: #{inspect(failures, pretty: true)}",
          failures,
          module
        )
    end
  end
end
