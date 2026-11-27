# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.Given do
  @moduledoc """
  A reusable given context: facts several specs start from, named for the situation (`an_open_account`). It
  is the counterpart of the `given` classes of the C# specs.

      defmodule MyApp.Accounts.Given.AnOpenAccount do
        use Cratis.Chronicle.Testing.Given

        @impl true
        def given(scenario), do: given_events(scenario, "account-1", %AccountOpened{owner: "Ada"})
      end

  Use it with the `given:` option of a scenario, which applies it before the spec's own `setup_all`, or in a
  pipeline with `given/2`; contexts compose by calling `given_context/2` on another one:

      use Cratis.Chronicle.Testing.EventScenario,
        event_types: MyApp.Events.all(),
        given: [MyApp.Accounts.Given.AnOpenAccount]

  A context is a script (`given/an_open_account.exs`) that stays out of a release, next to the specs that use
  it. Load the scripts of the `given` folders once, in `test/test_helper.exs`:

      for file <- Path.wildcard("lib/**/given/*.exs") |> Enum.sort(), do: Code.require_file(file)

  The functions work on every scenario of Chronicle, so a context does not depend on the kind of spec.
  """

  @callback given(scenario :: struct()) :: struct()
  @callback given(scenario :: struct(), argument :: term()) :: struct()
  @optional_callbacks given: 1, given: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Cratis.Chronicle.Testing.Given
      import Cratis.Chronicle.Testing.Given
    end
  end

  @doc "Appends events to an event source as facts that already happened."
  @spec given_events(struct(), String.t(), struct() | [struct()]) :: struct()
  def given_events(%module{} = scenario, event_source_id, events),
    do: module.given_events(scenario, event_source_id, events)

  @doc """
  Applies another given context to the scenario, for contexts that compose. It is not named `given/2`, so a
  context can define `given/2` (with an argument) itself.
  """
  @spec given_context(struct(), module() | {module(), term()} | (struct() -> struct())) ::
          struct()
  def given_context(%module{} = scenario, context), do: module.given(scenario, context)
end
