# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.ReadModelScenario do
  @moduledoc """
  A spec scenario for read models: the Elixir counterpart of `ReadModelScenario<TReadModel>`.

  Events are given and the spec states the read model they produce. A read model built by a
  **projection** (`from/2`, `removed_with/2`) is evaluated in memory by
  `Cratis.Chronicle.Testing.Projections` (the supported subset: no `join`, `children` or
  `from_every`); one built by a **reducer** is kept by the in-memory kernel's observers. Both are
  asked for the same way, by the module and the key (the event source id unless the model is keyed
  otherwise).

      defmodule MyApp.Accounts.ForAccount.WhenEventsAreProjected do
        use Cratis.Chronicle.Testing.ReadModelScenario,
          event_types: [MyApp.Accounts.AccountOpened, MyApp.Accounts.Deposited]

        alias MyApp.Accounts.{Account, AccountOpened, Deposited}

        setup_all %{scenario: scenario} do
          scenario =
            scenario
            |> given_events("account-1", [%AccountOpened{owner: "Ada"}, %Deposited{amount: 10}])

          %{scenario: scenario}
        end

        test "should have the owner", %{scenario: scenario} do
          should_have_read_model(scenario, Account, "account-1", %{owner: "Ada"})
        end

        test "should have the balance", %{scenario: scenario} do
          should_have_read_model(scenario, Account, "account-1", &(&1.balance == 10))
        end
      end

  `use` is the one of `Cratis.Chronicle.Testing.EventScenario` (same options and lifecycle; pass
  `reducers:` for reducer-built read models).

    * `given_events/3` - facts, in the order they happened
    * `read_model/3` - the read model (`nil` when there is none)
    * `should_have_read_model/4`, `should_not_have_read_model/3`
  """

  import Cratis.Chronicle.Testing.Scenarios, only: [fail: 3]

  alias Cratis.Chronicle.Testing
  alias Cratis.Chronicle.Testing.{Projections, Scenarios}

  defstruct [:client]

  @type t :: %__MODULE__{}

  defmacro __using__(opts), do: Scenarios.using(__MODULE__, opts)

  @doc "A scenario against a Chronicle test client."
  @spec new(atom()) :: t()
  def new(client), do: %__MODULE__{client: client}

  @doc """
  Applies a reusable given context: a module with `given/1` (or `{module, argument}` for `given/2`) or a
  1-arity function. Contexts compose: a context may call `given/2` for another one.
  """
  @spec given(t(), module() | {module(), term()} | (t() -> t())) :: t()
  def given(%__MODULE__{} = scenario, context), do: Scenarios.apply_given(scenario, [context])

  @doc "Appends `events` (one event or a list) to an event source, in order."
  @spec given_events(t(), String.t(), struct() | [struct()]) :: t()
  def given_events(%__MODULE__{} = scenario, event_source_id, events) do
    Scenarios.given_events(scenario.client, event_source_id, events)
    scenario
  end

  @doc "The read model `module` holds for `key`, or `nil`."
  @spec read_model(t(), module(), String.t()) :: struct() | nil
  def read_model(%__MODULE__{client: client}, module, key) do
    if function_exported?(module, :__chronicle_reducer__, 1) do
      {:ok, model} = Testing.read_model(client, module, to_string(key))
      model
    else
      project(client, module, to_string(key))
    end
  end

  @doc """
  The read model `module` should hold for `key` match `expected`: a 1-arity predicate, a struct
  (compared with `===`), or a map whose keys and values are all in the read model.
  """
  @spec should_have_read_model(
          t(),
          module(),
          String.t(),
          struct() | map() | (struct() -> boolean())
        ) :: t()
  def should_have_read_model(scenario, module, key, expected) do
    model = read_model(scenario, module, key)

    cond do
      model == nil ->
        fail(
          "Expected #{inspect(module)} to have a read model for #{inspect(key)}, but there is none",
          nil,
          expected
        )

      conforms?(model, expected) ->
        scenario

      true ->
        fail(
          "Expected the read model of #{inspect(key)} to match #{inspect(expected, pretty: true)}",
          model,
          expected
        )
    end
  end

  @doc "There should be no read model of `module` for `key`."
  @spec should_not_have_read_model(t(), module(), String.t()) :: t()
  def should_not_have_read_model(scenario, module, key) do
    case read_model(scenario, module, key) do
      nil ->
        scenario

      model ->
        fail(
          "Expected no read model for #{inspect(key)}, found: #{inspect(model, pretty: true)}",
          model,
          nil
        )
    end
  end

  defp conforms?(model, expected) when is_function(expected, 1), do: expected.(model) == true
  defp conforms?(model, %{__struct__: _} = expected), do: model === expected

  defp conforms?(model, expected) when is_map(expected),
    do: Enum.all?(expected, fn {k, v} -> Map.fetch(model, k) == {:ok, v} end)

  defp project(client, module, key) do
    client
    |> Testing.appended_events(key)
    |> Enum.reject(&is_nil(&1.event))
    |> Enum.reduce(nil, fn appended, instance ->
      case Projections.apply_event(module, instance, appended.event, key) do
        {:ok, next} -> next
        :removed -> nil
      end
    end)
  end
end
