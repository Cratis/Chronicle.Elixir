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

  alias Chronicle.Correlation.CorrelationId
  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.ReadModels.{DecisionConflict, DecisionRead}

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

  The caller owns the unit of work: complete it with `commit/1` or `rollback/1`, and stop its
  process with `Agent.stop/1` when done. `decide/2` and `with_unit_of_work/2` do both for you.
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
    ensure_no_decision_read_conflict!(state, event)

    Agent.update(unit_of_work, fn current_state ->
      current_state
      |> apply_transaction_context(event_sequence_id, opts)
      |> Map.update!(:events, &(&1 ++ [event]))
    end)
  end

  @doc """
  Enrolls a `Chronicle.ReadModels.DecisionRead` as a decision dependency of the unit of work.

  Reads of the same event source merge: the commit guards against anything appended since the
  **earliest** of their boundaries, across the **union** of their event types. Raises
  `ArgumentError` when the same event source already carries an explicit `:concurrency_scope`
  from a buffered event — the two guards cannot both apply, and silently picking one would
  hide that the caller asked for both.
  """
  @spec add_decision_read(t(), DecisionRead.t()) :: :ok
  def add_decision_read(unit_of_work, %DecisionRead{} = read) do
    state = Agent.get(unit_of_work, & &1)
    ensure_mutable!(state)
    ensure_decision_read_target!(state, read)
    ensure_no_concurrency_scope_conflict!(state, read.event_source_id)

    Agent.update(unit_of_work, fn current_state ->
      current_state
      |> apply_decision_read_context(read)
      |> Map.update!(:decision_reads, fn reads ->
        Map.update(reads, read.event_source_id, read.scope, &merge_decision_scope(&1, read.scope))
      end)
    end)

    :ok
  end

  @doc """
  Returns the merged concurrency scopes enrolled via `add_decision_read/2`, keyed by event
  source id.
  """
  @spec get_decision_reads(t()) :: %{String.t() => Chronicle.Events.ConcurrencyScope.t()}
  def get_decision_reads(unit_of_work), do: Agent.get(unit_of_work, & &1.decision_reads)

  @doc """
  Returns whether any decision read has been enrolled via `add_decision_read/2`.
  """
  @spec has_decision_reads?(t()) :: boolean()
  def has_decision_reads?(unit_of_work),
    do: Agent.get(unit_of_work, &(map_size(&1.decision_reads) > 0))

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

  When the commit itself fails (`{:error, reason}`, for example when the kernel is unreachable),
  the unit of work stays open and current: retry `commit/1`, or call `rollback/1`.
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
  Rolls the unit of work back if the function raises. The function's return value is returned
  as-is and committed whatever it is. When this returns, the unit of work is completed and its
  process stopped.
  """
  @spec with_unit_of_work((t() -> result), keyword()) :: result when result: any()
  def with_unit_of_work(fun, opts \\ []) when is_function(fun, 1) do
    unit_of_work = begin(opts)

    try do
      result = fun.(unit_of_work)

      case commit(unit_of_work) do
        :ok ->
          result

        {:error, {:concurrency_violations, violations}} ->
          if has_decision_reads?(unit_of_work) do
            raise DecisionConflict, violations: violations
          else
            raise "failed committing unit of work: #{inspect({:concurrency_violations, violations})}"
          end

        {:error, reason} ->
          raise "failed committing unit of work: #{inspect(reason)}"
      end
    rescue
      error ->
        if not is_completed?(unit_of_work) do
          rollback(unit_of_work)
        end

        reraise error, __STACKTRACE__
    after
      release(unit_of_work)
    end
  end

  @doc """
  Runs a function inside a unit of work and commits it, returning `{:ok, result}` on success.

  Unlike `with_unit_of_work/2`, a conflict never raises: when the function enrolled at least one
  decision read (`Chronicle.ReadModels.DecisionReads.get/3`) and the commit is rejected because
  one of them is no longer current, this returns `{:error, %Chronicle.ReadModels.DecisionConflict{}}`
  instead. Any other commit failure is returned as `{:error, reason}`, after rolling the unit of
  work back so later appends from the process are not buffered into it.

  Returning `{:error, reason}` from `fun` rejects the decision: the unit of work is rolled back,
  nothing is written, and `{:error, reason}` is returned as-is. The unit of work is rolled back,
  and the error re-raised, if `fun` itself raises. When `decide/2` returns, its unit of work is
  completed and its process stopped, so don't keep the unit of work beyond `fun`.

      Chronicle.decide(fn _unit_of_work ->
        {:ok, read} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.Seat, "seat-5")
        if read.instance == nil, do: Chronicle.EventSequences.EventLog.append("seat-5", %SeatBooked{})
      end)
  """
  @spec decide((t() -> result), keyword()) :: {:ok, result} | {:error, term()} when result: any()
  def decide(fun, opts \\ []) when is_function(fun, 1) do
    unit_of_work = begin(opts)

    try do
      case fun.(unit_of_work) do
        {:error, _reason} = rejected ->
          rollback(unit_of_work)
          rejected

        result ->
          commit_decision(unit_of_work, result)
      end
    rescue
      error ->
        if not is_completed?(unit_of_work) do
          rollback(unit_of_work)
        end

        reraise error, __STACKTRACE__
    after
      release(unit_of_work)
    end
  end

  defp commit_decision(unit_of_work, result) do
    case commit(unit_of_work) do
      :ok ->
        {:ok, result}

      {:error, {:concurrency_violations, violations}} ->
        if has_decision_reads?(unit_of_work) do
          {:error, %DecisionConflict{violations: violations}}
        else
          {:error, {:concurrency_violations, violations}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `decide/2` and `with_unit_of_work/2` own the unit of work they begin: once the call returns,
  # it is completed (rolled back if nothing else completed it, which also stops it being current)
  # and its process is stopped, so a long-lived caller does not accumulate one per call.
  defp release(unit_of_work) do
    if Process.alive?(unit_of_work) do
      if not is_completed?(unit_of_work) do
        rollback(unit_of_work)
      end

      Process.unlink(unit_of_work)
      Agent.stop(unit_of_work)
    end

    :ok
  catch
    :exit, _reason -> :ok
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
      decision_reads: %{},
      commit_fun:
        Keyword.get(opts, :commit_fun, &Chronicle.EventSequences.EventLog.commit_transaction/1)
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

  defp apply_decision_read_context(state, %DecisionRead{} = read) do
    state
    |> put_if_present(:event_sequence_id, read.event_sequence_id)
    |> put_if_present(:namespace, read.namespace)
  end

  defp ensure_decision_read_target!(state, %DecisionRead{} = read) do
    cond do
      state.namespace not in [nil, ""] and state.namespace != read.namespace ->
        raise ArgumentError, "unit of work already targets namespace #{inspect(state.namespace)}"

      state.event_sequence_id not in [nil, ""] and
          state.event_sequence_id != read.event_sequence_id ->
        raise ArgumentError,
              "unit of work already targets event sequence #{inspect(state.event_sequence_id)}"

      true ->
        :ok
    end
  end

  defp ensure_no_concurrency_scope_conflict!(state, event_source_id) do
    if Enum.any?(state.events, fn event ->
         event.event_source_id == event_source_id and not is_nil(event.concurrency_scope)
       end) do
      raise ArgumentError,
            "event source #{inspect(event_source_id)} already has an explicit concurrency " <>
              "scope; it cannot also be enrolled as a decision read"
    end
  end

  defp ensure_no_decision_read_conflict!(%{decision_reads: reads}, %EventForEventSourceId{
         event_source_id: event_source_id,
         concurrency_scope: scope
       })
       when not is_nil(scope) do
    if Map.has_key?(reads, event_source_id) do
      raise ArgumentError,
            "event source #{inspect(event_source_id)} is already enrolled as a decision read; " <>
              "it cannot also carry an explicit concurrency scope"
    end
  end

  defp ensure_no_decision_read_conflict!(_state, _event), do: :ok

  # Merges two reads of the same event source at their earliest boundary, across the union of
  # their event types. A stream/source-type narrowing is kept only when both reads agree on it;
  # otherwise it widens to "the whole event source" rather than silently keeping just one side's.
  defp merge_decision_scope(existing, new_scope) do
    {boundary, expects_no_matching_event} = merge_boundary(existing, new_scope)
    types = Enum.uniq(existing.event_types ++ new_scope.event_types)

    same_stream? =
      existing.event_stream_type == new_scope.event_stream_type and
        existing.event_stream_id == new_scope.event_stream_id

    %{
      existing
      | sequence_number: boundary,
        expects_no_matching_event: expects_no_matching_event,
        event_types: types,
        event_stream_type: if(same_stream?, do: existing.event_stream_type, else: ""),
        event_stream_id: if(same_stream?, do: existing.event_stream_id, else: ""),
        event_source_type:
          if(existing.event_source_type == new_scope.event_source_type,
            do: existing.event_source_type,
            else: ""
          )
    }
  end

  # A scope expecting no matching event carries the "nothing has happened yet" sentinel as its
  # sequence number (see Chronicle.Events.ConcurrencyScope.expecting_no_matching_event/1), which
  # a plain min/2 over sequence numbers would treat as the *latest* possible boundary instead of
  # the earliest - exactly backwards. Prefer whichever side still expects nothing, since that is
  # the stricter guard; between two such reads, their sequence numbers are both the sentinel, so
  # either side's is fine.
  defp merge_boundary(%{expects_no_matching_event: true} = existing, %{
         expects_no_matching_event: true
       }),
       do: {existing.sequence_number, true}

  defp merge_boundary(%{expects_no_matching_event: true} = existing, _new_scope),
    do: {existing.sequence_number, true}

  defp merge_boundary(_existing, %{expects_no_matching_event: true} = new_scope),
    do: {new_scope.sequence_number, true}

  defp merge_boundary(existing, new_scope),
    do: {min(existing.sequence_number, new_scope.sequence_number), false}

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
