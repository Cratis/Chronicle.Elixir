# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.BatchFunctions do
  @moduledoc false

  # Captures the batch functions of a reactor or reducer and checks them when the observer
  # registers.
  #
  # A batch function is a function preceded by one or more `@observes EventType` attributes,
  # the Elixir counterpart of .NET's `[Observes<TEvent>]`. `__on_definition__/6` runs for every
  # function the observer defines; when `@observes` values are pending it records the function
  # and the event types, and clears them so they only apply to that function.
  #
  # `validate!/2` enforces that each event type reaches exactly one function, with the same
  # rules as the .NET client, and raises the matching exception from Chronicle.Observers.

  alias Chronicle.Observers.{
    BatchFunctionObservesUnknownEventType,
    EventTypeObservedByMoreThanOneFunction,
    InvalidBatchFunction,
    ObservesOnlyOnBatchFunctions,
    PerEventCallbackMissing,
    ReducerHasMoreThanOneBatchFunction,
    ReducerMixesBatchAndPerEventFunctions
  }

  @typedoc "A captured batch function: its name, arity, kind and the event types it observes."
  @type captured :: {atom(), non_neg_integer(), :def | :defp | atom(), [module()]}

  @typedoc "The checked functions of an observer."
  @type t :: %{batch: [{atom(), [module()]}], per_event: [module()]}

  @doc false
  def __on_definition__(env, kind, name, args, _guards, _body) do
    case Module.get_attribute(env.module, :observes) do
      [] ->
        :ok

      # The functions the observer macros generate themselves.
      _observed when name in [:__chronicle_reactor__, :__chronicle_reducer__] ->
        :ok

      observed ->
        Module.delete_attribute(env.module, :observes)

        Module.put_attribute(
          env.module,
          :chronicle_batch_functions,
          {name, length(args), kind, Enum.reverse(observed)}
        )
    end
  end

  @doc """
  Merges captured entries that belong to the same function (`@observes` before more than one
  of its clauses), keeping the order functions were defined in.
  """
  @spec merge([captured()]) :: [captured()]
  def merge(captured) do
    captured
    |> Enum.reduce([], fn {name, arity, kind, observed}, acc ->
      case List.keyfind(acc, {name, arity}, 0) do
        nil ->
          [{{name, arity}, kind, observed} | acc]

        {key, existing_kind, existing} ->
          List.keyreplace(acc, key, 0, {key, existing_kind, existing ++ observed})
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {{name, arity}, kind, observed} ->
      {name, arity, kind, Enum.uniq(observed)}
    end)
  end

  @doc """
  Checks the batch functions and per-event event types of a reactor or reducer module, raising
  when an event type would reach more than one function or a function has the wrong shape.
  """
  @spec validate!(:reactor | :reducer, module()) :: t()
  def validate!(:reactor, module) do
    check!(module, %{
      captured: module.__chronicle_reactor__(:batch_functions),
      per_event: module.__chronicle_reactor__(:per_event),
      per_event_callbacks: [handle: 2, handle_replay: 2],
      required_callback: {:handle, 2},
      batch_arity: 2,
      batch_shape: "a reactor batch function takes (batch, context)"
    })
  end

  def validate!(:reducer, module) do
    functions =
      check!(module, %{
        captured: module.__chronicle_reducer__(:batch_functions),
        per_event: module.__chronicle_reducer__(:per_event),
        per_event_callbacks: [reduce: 3],
        required_callback: {:reduce, 3},
        batch_arity: 3,
        batch_shape: "a reducer batch function takes (batch, current, context)"
      })

    cond do
      length(functions.batch) > 1 ->
        raise ReducerHasMoreThanOneBatchFunction, observer: module

      functions.batch != [] and functions.per_event != [] ->
        raise ReducerMixesBatchAndPerEventFunctions, observer: module

      true ->
        functions
    end
  end

  defp check!(module, spec) do
    batch = Enum.map(spec.captured, &check_function!(module, spec, &1))
    check_reaches_one_function!(module, batch, spec.per_event)

    {callback, arity} = spec.required_callback

    if spec.per_event != [] and not function_exported?(module, callback, arity) do
      raise PerEventCallbackMissing, observer: module, callback: "#{callback}/#{arity}"
    end

    %{batch: batch, per_event: spec.per_event}
  end

  defp check_function!(module, spec, {name, arity, kind, observed}) do
    cond do
      {name, arity} in spec.per_event_callbacks ->
        raise ObservesOnlyOnBatchFunctions, observer: module, function: "#{name}/#{arity}"

      kind != :def ->
        raise InvalidBatchFunction,
          observer: module,
          function: "#{name}/#{arity}",
          expected: "it must be public (def), #{spec.batch_shape}"

      arity != spec.batch_arity ->
        raise InvalidBatchFunction,
          observer: module,
          function: "#{name}/#{arity}",
          expected: spec.batch_shape

      true ->
        Enum.each(observed, &check_event_type!(module, name, arity, &1))
        {name, observed}
    end
  end

  defp check_event_type!(module, name, arity, event_type) do
    unless is_atom(event_type) and Code.ensure_loaded?(event_type) and
             function_exported?(event_type, :__chronicle_event_type__, 1) do
      raise BatchFunctionObservesUnknownEventType,
        observer: module,
        function: "#{name}/#{arity}",
        event_type: event_type
    end
  end

  defp check_reaches_one_function!(module, batch, per_event) do
    all = Enum.flat_map(batch, fn {_name, observed} -> observed end) ++ Enum.uniq(per_event)

    case all -- Enum.uniq(all) do
      [] ->
        :ok

      [duplicate | _] ->
        raise EventTypeObservedByMoreThanOneFunction, observer: module, event_type: duplicate
    end
  end
end
