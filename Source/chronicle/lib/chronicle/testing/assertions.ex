# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Assertions do
  @moduledoc """
  ExUnit assertions for events appended to a `Chronicle.Testing.start_supervised_client/1`
  client, and for the structured rejections `Chronicle.EventSequences.EventLog` returns.

      import Chronicle.Testing.Assertions

      :ok = Chronicle.EventSequences.EventLog.append("account-1", %AccountOpened{}, client: client)
      assert_appended(client, %AccountOpened{}, event_source_id: "account-1")

      {:error, _} = Chronicle.EventSequences.EventLog.append("account-1", %AccountOpened{}, client: client)
      assert_constraint_violation(result, "UniqueAccount")
  """

  import ExUnit.Assertions

  alias Chronicle.Testing

  @doc """
  Asserts that at least one appended event matches `matcher`.

  `matcher` is an exact event struct (compared with `==`), an event type module
  (matches any event of that type), or a 1-arity function predicate.

  ## Options

    * `:event_source_id` — only consider events appended for this event source
    * `:count` — assert exactly this many matches, instead of "at least one"
  """
  @spec assert_appended(atom(), struct() | module() | (struct() -> boolean()), keyword()) :: true
  def assert_appended(client, matcher, opts \\ []) do
    matches = matching_events(client, matcher, opts)
    count = Keyword.get(opts, :count)

    cond do
      count != nil and length(matches) != count ->
        flunk(
          "expected #{count} event(s) matching #{inspect(matcher)}, got #{length(matches)}: " <>
            inspect(matches)
        )

      count == nil and matches == [] ->
        flunk("expected an event matching #{inspect(matcher)}, but none was appended")

      true ->
        true
    end
  end

  @doc """
  Asserts that no appended event matches `matcher`. See `assert_appended/3` for
  the accepted matcher shapes and options.
  """
  @spec refute_appended(atom(), struct() | module() | (struct() -> boolean()), keyword()) :: false
  def refute_appended(client, matcher, opts \\ []) do
    case matching_events(client, matcher, opts) do
      [] ->
        false

      matches ->
        flunk("expected no event matching #{inspect(matcher)}, but found: #{inspect(matches)}")
    end
  end

  @doc """
  Asserts that `result` (as returned by `Chronicle.EventSequences.EventLog.append/3` and
  friends) is a constraint-violation rejection, optionally for the named constraint.
  """
  @spec assert_constraint_violation(term(), String.t() | nil) :: true
  def assert_constraint_violation(result, constraint_name \\ nil) do
    case result do
      {:error, {:constraint_violations, violations}} ->
        if constraint_name do
          names = Enum.map(violations, &constraint_name_of/1)

          unless constraint_name in names do
            flunk(
              "expected a constraint violation for #{inspect(constraint_name)}, got: #{inspect(names)}"
            )
          end
        end

        true

      other ->
        flunk("expected {:error, {:constraint_violations, _}}, got: #{inspect(other)}")
    end
  end

  @doc """
  Asserts that `result` is a concurrency-violation rejection.
  """
  @spec assert_concurrency_violation(term()) :: true
  def assert_concurrency_violation(result) do
    case result do
      {:error, {:concurrency_violations, _violations}} ->
        true

      other ->
        flunk("expected {:error, {:concurrency_violations, _}}, got: #{inspect(other)}")
    end
  end

  defp constraint_name_of(violation),
    do: Map.get(violation, :ConstraintName, Map.get(violation, :constraint_name))

  defp matching_events(client, matcher, opts) do
    events =
      case Keyword.get(opts, :event_source_id) do
        nil -> all_decoded_events(Testing.kernel_for(client))
        event_source_id -> Testing.appended_events(client, event_source_id)
      end

    events
    |> Enum.map(& &1.event)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&matches?(&1, matcher))
  end

  defp all_decoded_events(nil), do: []

  defp all_decoded_events(kernel) do
    event_types = Chronicle.Testing.InMemoryKernel.event_types(kernel)

    kernel
    |> Chronicle.Testing.InMemoryKernel.all_wire_events()
    |> Enum.map(&Chronicle.Events.AppendedEvent.from_wire(&1, event_types))
  end

  defp matches?(event, %module{} = expected) when event.__struct__ == module,
    do: event == expected

  defp matches?(_event, %_module{}), do: false
  defp matches?(event, module) when is_atom(module), do: event.__struct__ == module
  defp matches?(event, matcher) when is_function(matcher, 1), do: matcher.(event)
end
