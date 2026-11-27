# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.EventScenario do
  @moduledoc """
  A spec scenario for events and the constraints on them: the Elixir counterpart of `EventScenario`.

  Events are given, an append is performed **once**, and every `test` states one expectation with a
  `should_*` function. The append goes through the real `Cratis.Chronicle.EventSequences.EventLog`
  against the in-memory kernel, so constraints (`unique/2`, `unique_event_type/1`), concurrency scopes
  and sequence numbers are the real ones.

      defmodule MyApp.Accounts.ForAccountOpened.WhenOpeningTwice do
        use Cratis.Chronicle.Testing.EventScenario,
          event_types: [MyApp.Accounts.AccountOpened]

        alias MyApp.Accounts.AccountOpened

        setup_all %{scenario: scenario} do
          scenario =
            scenario
            |> given_events("account-1", %AccountOpened{owner: "Ada"})
            |> append("account-1", %AccountOpened{owner: "Ada"})

          %{scenario: scenario}
        end

        test "should be refused by the constraint", %{scenario: scenario} do
          should_have_constraint_violation(scenario, "credential-created")
        end

        test "should keep only the first event", %{scenario: scenario} do
          should_have_tail_sequence_number(scenario, 0)
        end
      end

  `use` starts the in-memory kernel once for the module (`lifecycle: :shared`, the default) or before
  every test (`lifecycle: :per_test`, with `setup` instead of `setup_all`), puts the scenario in the
  context as `:scenario`, and imports this module. Options: `:lifecycle`, `:async` (default `true`)
  and every option of `Cratis.Chronicle.Testing.start_supervised_client/1`.

  A scenario is an immutable value: **given** and **because** functions return the next scenario,
  **should** functions check it and return it, so they chain.

    * `given_events/3` - facts that already happened
    * `append/4` - appends events, and keeps the outcome
    * `should_be_successful/1`, `should_have_constraint_violation/1,2`,
      `should_have_concurrency_violation/1`
    * `should_have_appended/2,3`, `should_not_have_appended/2,3`, `should_have_appended_exactly/2`,
      `should_not_have_appended_any_events/1`, `should_have_tail_sequence_number/2`

  Events are matched by an exact struct, an event type module, or a 1-arity predicate; only the events
  appended **by `append/4`** (and by reactors it triggered) count, not the given ones.
  """

  import Cratis.Chronicle.Testing.Scenarios,
    only: [appended_since: 2, describe: 1, fail: 1, fail: 3, matches?: 2]

  alias Cratis.Chronicle.EventSequences.EventLog
  alias Cratis.Chronicle.Testing
  alias Cratis.Chronicle.Testing.{Assertions, Scenarios}

  defstruct [:client, :result, :appended?, baseline: 0, failures: []]

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

  @doc "Appends `events` (one event or a list) to an event source before the behavior under specification."
  @spec given_events(t(), String.t(), struct() | [struct()]) :: t()
  def given_events(%__MODULE__{} = scenario, event_source_id, events) do
    Scenarios.given_events(scenario.client, event_source_id, events)
    scenario
  end

  @doc """
  Appends `events` to an event source and keeps the outcome (`:ok`, or the refusal). Options are those
  of `Cratis.Chronicle.EventSequences.EventLog.append_many/3`.
  """
  @spec append(t(), String.t(), struct() | [struct()], keyword()) :: t()
  def append(%__MODULE__{} = scenario, event_source_id, events, opts \\ []) do
    baseline = length(Scenarios.all_events(scenario.client))

    result =
      EventLog.append_many(
        to_string(event_source_id),
        List.wrap(events),
        [client: scenario.client] ++ opts
      )

    failures =
      case Testing.wait_for_observers(scenario.client) do
        :ok -> []
        {:error, failures} -> failures
      end

    %{scenario | result: result, baseline: baseline, appended?: true, failures: failures}
  end

  @doc "What the append returned: `:ok`, or `{:error, reason}`."
  @spec result(t()) :: :ok | {:error, term()}
  def result(%__MODULE__{appended?: nil}),
    do: fail("the scenario has not appended anything yet; call append/4 first")

  def result(%__MODULE__{result: result}), do: result

  @doc "The append should have been accepted."
  @spec should_be_successful(t()) :: t()
  def should_be_successful(scenario) do
    case result(scenario) do
      :ok ->
        scenario

      other ->
        fail(
          "Expected the append to be accepted, got: #{inspect(other, pretty: true)}",
          other,
          :ok
        )
    end
  end

  @doc "The append should have been refused because a constraint (by name, when given) was violated."
  @spec should_have_constraint_violation(t(), String.t() | nil) :: t()
  def should_have_constraint_violation(scenario, name \\ nil) do
    Assertions.assert_constraint_violation(result(scenario), name)
    scenario
  end

  @doc "The append should have been refused because of a concurrency violation."
  @spec should_have_concurrency_violation(t()) :: t()
  def should_have_concurrency_violation(scenario) do
    Assertions.assert_concurrency_violation(result(scenario))
    scenario
  end

  @doc """
  An event matching `matcher` (an exact struct, an event type module or a predicate) should have been
  appended. Options: `:event_source_id` limits it to one event source, `:count` asks for exactly that many.
  """
  @spec should_have_appended(t(), struct() | module() | (struct() -> boolean()), keyword()) :: t()
  def should_have_appended(scenario, matcher, opts \\ []) do
    matched = matching(scenario, matcher, opts)
    count = Keyword.get(opts, :count)

    cond do
      count != nil and length(matched) != count ->
        fail(
          "Expected #{count} appended event(s) matching #{describe(matcher)}, got #{length(matched)}",
          appended(scenario),
          matcher
        )

      count == nil and matched == [] ->
        fail(
          "Expected #{describe(matcher)} to be appended, but these were: #{inspect(appended(scenario), pretty: true)}",
          appended(scenario),
          matcher
        )

      true ->
        scenario
    end
  end

  @doc "No event matching `matcher` should have been appended (see `should_have_appended/3`)."
  @spec should_not_have_appended(t(), struct() | module() | (struct() -> boolean()), keyword()) ::
          t()
  def should_not_have_appended(scenario, matcher, opts \\ []) do
    case matching(scenario, matcher, opts) do
      [] ->
        scenario

      matched ->
        fail(
          "Expected no appended event matching #{describe(matcher)}, but found: #{inspect(matched, pretty: true)}",
          matched,
          matcher
        )
    end
  end

  @doc "Exactly these events should have been appended, in this order; each element is a matcher."
  @spec should_have_appended_exactly(t(), [struct() | module() | (struct() -> boolean())]) :: t()
  def should_have_appended_exactly(scenario, matchers) when is_list(matchers) do
    events = appended(scenario)

    ok? =
      length(events) == length(matchers) and
        Enum.zip(events, matchers)
        |> Enum.all?(fn {event, matcher} -> matches?(event, matcher) end)

    if ok?,
      do: scenario,
      else:
        fail(
          "Expected exactly #{inspect(Enum.map(matchers, &describe/1))} to be appended",
          events,
          matchers
        )
  end

  @doc "Nothing should have been appended."
  @spec should_not_have_appended_any_events(t()) :: t()
  def should_not_have_appended_any_events(scenario) do
    case appended(scenario) do
      [] ->
        scenario

      events ->
        fail(
          "Expected nothing to be appended, but found: #{inspect(events, pretty: true)}",
          events,
          []
        )
    end
  end

  @doc "The event log's tail (the sequence number of its last event, counted from 0) should be `expected`."
  @spec should_have_tail_sequence_number(t(), non_neg_integer()) :: t()
  def should_have_tail_sequence_number(%__MODULE__{client: client} = scenario, expected) do
    case EventLog.get_tail_sequence_number(nil, client: client) do
      {:ok, ^expected} ->
        scenario

      {:ok, actual} ->
        fail(
          "Expected the tail sequence number to be #{expected}, got #{actual}",
          actual,
          expected
        )

      other ->
        fail("Could not read the tail sequence number: #{inspect(other)}")
    end
  end

  @doc "The reactors and reducers that ran should not have failed."
  @spec should_not_have_observer_failures(t()) :: t()
  def should_not_have_observer_failures(%__MODULE__{failures: []} = scenario), do: scenario

  def should_not_have_observer_failures(%__MODULE__{failures: failures}),
    do:
      fail("Expected no observer failures, got: #{inspect(failures, pretty: true)}", failures, [])

  @doc false
  def appended(%__MODULE__{client: client, baseline: baseline}),
    do: client |> appended_since(baseline) |> Enum.map(&elem(&1, 1))

  defp matching(%__MODULE__{client: client, baseline: baseline}, matcher, opts) do
    only = Keyword.get(opts, :event_source_id)

    for {event_source_id, event} <- appended_since(client, baseline),
        only == nil or event_source_id == only,
        matches?(event, matcher),
        do: event
  end
end
