# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.Scenarios do
  @moduledoc false

  # What the event, read model and reactor scenarios share.

  alias Cratis.Chronicle.EventSequences.EventLog
  alias Cratis.Chronicle.Events.AppendedEvent
  alias Cratis.Chronicle.Testing
  alias Cratis.Chronicle.Testing.InMemoryKernel

  @doc "The `use` body: starts the kernel once per module (`:shared`) or per test (`:per_test`)."
  def using(scenario_module, opts) do
    {lifecycle, opts} = Keyword.pop(opts, :lifecycle, :shared)
    {given, opts} = Keyword.pop(opts, :given, [])
    {prepare, opts} = Keyword.pop(opts, :setup)
    {async, chronicle_opts} = Keyword.pop(opts, :async, true)

    setup = if lifecycle == :per_test, do: :setup, else: :setup_all

    quote do
      use ExUnit.Case, async: unquote(async)

      import unquote(scenario_module)

      unquote(setup)() do
        {:ok, client} = Cratis.Chronicle.Testing.start_supervised_client(unquote(chronicle_opts))

        ExUnit.Callbacks.on_exit(fn ->
          Cratis.Chronicle.Testing.stop_supervised_client(client)
        end)

        context = Cratis.Chronicle.Testing.Scenarios.prepare(unquote(prepare), client)

        scenario =
          client
          |> unquote(scenario_module).new()
          |> Cratis.Chronicle.Testing.Scenarios.apply_given(unquote(given))

        Map.put(context, :scenario, scenario)
      end
    end
  end

  @doc """
  Runs the `setup:` function of a spec module, `{module, function}`, with the client and returns what it
  adds to the context (a map, a keyword list, or `:ok`). It runs in the process of the setup, so
  `start_supervised!/1` and `on_exit/1` work there, and before the given contexts.
  """
  def prepare(nil, _client), do: %{}

  def prepare({module, function}, client) do
    case apply(module, function, [client]) do
      :ok -> %{}
      context -> Map.new(context)
    end
  end

  @doc """
  Applies given contexts to a scenario, in order. A context is a module with `given/1`, `{module, argument}`
  for one with `given/2`, or a 1-arity function.
  """
  def apply_given(scenario, contexts),
    do: contexts |> List.wrap() |> Enum.reduce(scenario, &apply_context/2)

  defp apply_context({module, argument}, scenario) when is_atom(module),
    do: module.given(scenario, argument)

  defp apply_context(module, scenario) when is_atom(module), do: module.given(scenario)
  defp apply_context(function, scenario) when is_function(function, 1), do: function.(scenario)

  @doc "Appends `events` to an event source as the given facts of a scenario, and lets the observers run."
  def given_events(client, event_source_id, events) do
    case EventLog.append_many(to_string(event_source_id), List.wrap(events), client: client) do
      :ok -> :ok
      other -> fail("the given events were refused: #{inspect(other)}")
    end

    Testing.wait_for_observers(client)
  end

  @doc "Every event in the store, decoded, in append order."
  def all_events(client) do
    case Testing.kernel_for(client) do
      nil ->
        []

      kernel ->
        event_types = InMemoryKernel.event_types(kernel)

        kernel
        |> InMemoryKernel.all_wire_events()
        |> Enum.map(&AppendedEvent.from_wire(&1, event_types))
    end
  end

  @doc "The events appended after the first `baseline`, as `{event_source_id, event}` pairs."
  def appended_since(client, baseline) do
    client
    |> all_events()
    |> Enum.drop(baseline)
    |> Enum.reject(&is_nil(&1.event))
    |> Enum.map(&{&1.context.event_source_id, &1.event})
  end

  @doc "Whether `event` matches an exact struct, an event type module or a 1-arity predicate."
  def matches?(event, matcher) when is_function(matcher, 1), do: matcher.(event) == true
  def matches?(event, matcher) when is_atom(matcher), do: match?(%{__struct__: ^matcher}, event)
  def matches?(event, matcher), do: event == matcher

  @doc "A short, readable description of a matcher for failure messages."
  def describe(matcher) when is_function(matcher), do: "an event satisfying the predicate"
  def describe(matcher), do: inspect(matcher)

  @doc "Raises an `ExUnit.AssertionError` carrying `message` and, when given, the two sides."
  def fail(message, left \\ nil, right \\ nil) do
    raise ExUnit.AssertionError, message: message, left: left, right: right
  end
end
