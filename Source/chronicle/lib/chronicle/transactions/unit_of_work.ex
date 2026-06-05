# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.UnitOfWork do
  @moduledoc """
  Buffers event appends and commits them as a single Chronicle append-many operation.

  Use `begin/1` to create a unit of work and make it current for the calling
  process. Calls to `Chronicle.append/3`, `Chronicle.append_many/3`, or a
  transactional event sequence are buffered until `commit/1` is called.
  """

  use Agent

  alias Chronicle.{CorrelationId, EventSequences.EventForEventSourceId}

  alias Chronicle.Transactions.{
    UnitOfWorkIsAlreadyCommitted,
    UnitOfWorkIsAlreadyRolledBack,
    UnitOfWorkManager
  }

  @type t :: pid()
  @type on_completed :: (t() -> any())
  @type commit_fun :: (map() -> {:ok, map()} | {:error, term()})

  @doc """
  Begins a new unit of work and makes it current for the calling process.
  """
  @spec begin(keyword()) :: t()
  def begin(opts \\ []), do: UnitOfWorkManager.begin(opts)

  @doc """
  Returns the current unit of work for the calling process.
  """
  @spec current() :: t()
  def current, do: UnitOfWorkManager.current()

  @doc """
  Returns whether the calling process currently has an active unit of work.
  """
  @spec has_current?() :: boolean()
  def has_current?, do: UnitOfWorkManager.has_current?()

  @doc """
  Sets an existing unit of work as current for the calling process.
  """
  @spec set_current(t()) :: t()
  def set_current(unit_of_work), do: UnitOfWorkManager.set_current(unit_of_work)

  @doc """
  Tries to get a unit of work by correlation id.
  """
  @spec try_get_for(CorrelationId.t() | String.t()) :: {:ok, t()} | :error
  def try_get_for(correlation_id), do: UnitOfWorkManager.try_get_for(correlation_id)

  @doc false
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts) do
    Agent.start_link(fn -> new_state(opts) end)
  end

  @doc """
  Returns the correlation id for a unit of work.
  """
  @spec correlation_id(t()) :: CorrelationId.t()
  def correlation_id(unit_of_work) do
    Agent.get(unit_of_work, & &1.correlation_id)
  end

  @doc """
  Returns whether the unit of work has been committed or rolled back.
  """
  @spec is_completed?(t()) :: boolean()
  def is_completed?(unit_of_work) do
    Agent.get(unit_of_work, &(&1.committed? or &1.rolled_back?))
  end

  @doc """
  Returns whether the unit of work completed successfully.
  """
  @spec is_success?(t()) :: boolean()
  def is_success?(unit_of_work) do
    Agent.get(unit_of_work, & &1.success?)
  end

  @doc """
  Registers a callback that runs when the unit of work is committed or rolled back.
  """
  @spec on_completed(t(), on_completed()) :: :ok
  def on_completed(unit_of_work, callback) when is_function(callback, 1) do
    Agent.update(unit_of_work, fn state ->
      %{state | callbacks: state.callbacks ++ [callback]}
    end)
  end

  @doc """
  Adds an event to the unit of work.
  """
  @spec add_event(t(), String.t(), EventForEventSourceId.t(), keyword()) :: :ok
  def add_event(unit_of_work, event_sequence_id, %EventForEventSourceId{} = event, opts \\ []) do
    state = Agent.get(unit_of_work, & &1)
    ensure_mutable!(state)
    validate_transaction_context!(state, event_sequence_id, opts)

    Agent.update(unit_of_work, fn current_state ->
      current_state
      |> apply_transaction_context(event_sequence_id, opts)
      |> Map.update!(:events, &(&1 ++ [event]))
    end)
  end

  @doc """
  Returns the buffered events in insertion order.
  """
  @spec get_events(t()) :: [EventForEventSourceId.t()]
  def get_events(unit_of_work) do
    Agent.get(unit_of_work, & &1.events)
  end

  @doc """
  Returns the last committed sequence number if available.
  """
  @spec last_committed_sequence_number(t()) :: non_neg_integer() | nil
  def last_committed_sequence_number(unit_of_work) do
    Agent.get(unit_of_work, & &1.last_sequence_number)
  end

  @doc """
  Commits the buffered events.
  """
  @spec commit(t()) :: :ok | {:error, term()}
  def commit(unit_of_work) do
    state = Agent.get(unit_of_work, & &1)
    ensure_mutable!(state)

    case state.commit_fun.(state) do
      {:ok, result} ->
        Agent.update(unit_of_work, fn current_state ->
          %{
            current_state
            | append_results: Map.get(result, :append_results, []),
              constraint_violations: Map.get(result, :constraint_violations, []),
              append_errors: Map.get(result, :append_errors, []),
              last_sequence_number: Map.get(result, :last_sequence_number),
              committed?: true,
              success?: Map.get(result, :success?, true)
          }
        end)

        run_callbacks(unit_of_work)

        case Map.get(result, :error) do
          nil -> :ok
          error -> {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Rolls back the unit of work and clears the buffered events.
  """
  @spec rollback(t()) :: :ok
  def rollback(unit_of_work) do
    final_state =
      Agent.get_and_update(unit_of_work, fn state ->
        ensure_not_committed!(state)

        new_state = %{
          state
          | events: [],
            append_results: [],
            constraint_violations: [],
            append_errors: [],
            rolled_back?: true,
            success?: false
        }

        {new_state, new_state}
      end)

    run_callbacks(unit_of_work, final_state.callbacks)
    :ok
  end

  @doc """
  Runs a function inside a unit of work and commits it if the function succeeds.
  Rolls the unit of work back if the function raises.
  """
  @spec with_unit_of_work((t() -> result), keyword()) :: result when result: any()
  def with_unit_of_work(fun, opts \\ []) when is_function(fun, 1) do
    unit_of_work = begin(opts)

    try do
      result = fun.(unit_of_work)

      case commit(unit_of_work) do
        :ok -> result
        {:error, reason} -> raise "failed committing unit of work: #{inspect(reason)}"
      end
    rescue
      error ->
        if not is_completed?(unit_of_work) do
          rollback(unit_of_work)
        end

        reraise error, __STACKTRACE__
    end
  end

  @doc false
  def default_commit_result(sequence_numbers, constraint_violations, append_errors) do
    error =
      cond do
        constraint_violations != [] -> {:constraint_violations, constraint_violations}
        append_errors != [] -> {:append_errors, append_errors}
        true -> nil
      end

    %{
      append_results: sequence_numbers,
      sequence_numbers: sequence_numbers,
      constraint_violations: constraint_violations,
      append_errors: append_errors,
      last_sequence_number: List.last(sequence_numbers),
      success?: is_nil(error),
      error: error
    }
  end

  defp new_state(opts) do
    correlation_id = Keyword.fetch!(opts, :correlation_id)

    %{
      correlation_id: correlation_id,
      event_sequence_id: nil,
      client: nil,
      namespace: nil,
      events: [],
      append_results: [],
      constraint_violations: [],
      append_errors: [],
      last_sequence_number: nil,
      committed?: false,
      rolled_back?: false,
      success?: false,
      callbacks: [],
      commit_fun: Keyword.get(opts, :commit_fun, &Chronicle.EventLog.commit_transaction/1)
    }
  end

  defp validate_transaction_context!(state, event_sequence_id, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    namespace = Keyword.get(opts, :namespace)

    state
    |> ensure_same!(:event_sequence_id, event_sequence_id, "event sequence")
    |> ensure_same!(:client, client, "client")
    |> ensure_same!(:namespace, namespace, "namespace")

    :ok
  end

  defp apply_transaction_context(state, event_sequence_id, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    namespace = Keyword.get(opts, :namespace)

    state
    |> Map.put(:event_sequence_id, event_sequence_id)
    |> Map.put(:client, client)
    |> put_if_present(:namespace, namespace)
  end

  defp ensure_same!(state, _key, value, _label) when value in [nil, ""], do: state

  defp ensure_same!(state, key, value, label) do
    case Map.get(state, key) do
      nil ->
        state

      ^value ->
        state

      existing ->
        raise ArgumentError, "unit of work already targets #{label} #{inspect(existing)}"
    end
  end

  defp put_if_present(state, _key, value) when value in [nil, ""], do: state
  defp put_if_present(state, key, value), do: Map.put(state, key, value)

  defp ensure_mutable!(state) do
    ensure_not_committed!(state)
    ensure_not_rolled_back!(state)
  end

  defp ensure_not_committed!(%{committed?: true}), do: raise(UnitOfWorkIsAlreadyCommitted)
  defp ensure_not_committed!(_state), do: :ok

  defp ensure_not_rolled_back!(%{rolled_back?: true}), do: raise(UnitOfWorkIsAlreadyRolledBack)
  defp ensure_not_rolled_back!(_state), do: :ok

  defp run_callbacks(unit_of_work, callbacks \\ nil) do
    callbacks = callbacks || Agent.get(unit_of_work, & &1.callbacks)
    Enum.each(callbacks, & &1.(unit_of_work))
  end
end
