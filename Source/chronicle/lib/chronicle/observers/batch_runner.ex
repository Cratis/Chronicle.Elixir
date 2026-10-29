# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.BatchRunner do
  @moduledoc false

  # Runs the batches a reactor or reducer handler receives: concurrently across
  # partitions, in order within a partition (see PartitionScheduler), each in
  # its own process so the handler stays responsive while work runs.
  #
  # The handler keeps this runner's fields in its own state and calls in here
  # from its handle_info clauses. What differs between reactors and reducers is
  # passed in as `hooks`:
  #
  #   * `:kind` — `:reactor` or `:reducer`, for telemetry and logs.
  #   * `:build_result` — `(state, message) -> result` that runs the batch.
  #   * `:expired_result` — `(message, reason) -> result` answered for a batch
  #     the kernel has already given up on.
  #   * `:notify` — `(state, item) -> any` that runs an inline or barrier item
  #     (replay notifications) in the handler process.
  #
  # Telemetry:
  #
  #   * `[:chronicle, :observer, :batch, :start | :stop | :exception]` — a span
  #     around each batch with `observer`, `kind`, `partition` and `batch_size`
  #     metadata; `:stop` carries the `duration`.
  #   * `[:chronicle, :observer, :batch, :expired]` — a batch answered as
  #     expired without running, with the `waited` milliseconds.
  #   * `[:chronicle, :observer, :queue]` — `queue_depth` and `in_flight`
  #     measurements whenever work starts or finishes.

  alias Chronicle.Observers.{PartitionScheduler, ResultSender}

  @default_max_concurrent_partitions 16
  @expired_message "Delivery expired before handling: the kernel stopped waiting for its result"

  @doc "The fields a handler adds to its state for the runner."
  @spec init(keyword()) :: map()
  def init(opts) do
    max = Keyword.get(opts, :max_concurrent_partitions) || @default_max_concurrent_partitions

    %{
      scheduler: PartitionScheduler.new(max),
      batches: %{},
      generation: 0
    }
  end

  @doc """
  Queues a batch for `partition` received at `received_at` (monotonic
  milliseconds) and starts whatever can run.
  """
  @spec batch(map(), term(), map(), integer(), map()) :: map()
  def batch(state, partition, message, received_at, hooks) do
    state
    |> enqueue({:batch, partition, {message, received_at}})
    |> run(hooks)
  end

  @doc "Queues an item to run in the handler once `partition`'s earlier batches have finished."
  @spec inline(map(), term(), term(), map()) :: map()
  def inline(state, partition, item, hooks),
    do: state |> enqueue({:inline, partition, item}) |> run(hooks)

  @doc "Queues an item to run in the handler once everything before it has finished."
  @spec barrier(map(), term(), map()) :: map()
  def barrier(state, item, hooks), do: state |> enqueue({:barrier, item}) |> run(hooks)

  @doc """
  Handles a finished batch. Returns `{:ok, state}`, or `{:send_failed, state}`
  when its result could not be sent and the handler should reopen its stream.
  Results of batches from before the last `reset/1` are ignored.
  """
  @spec finished(map(), reference(), term(), map()) :: {:ok | :send_failed, map()}
  def finished(state, tag, outcome, hooks) do
    case Map.pop(state.batches, tag) do
      {nil, _} ->
        {:ok, state}

      {%{monitor: monitor, partition: partition, generation: generation}, batches} ->
        Process.demonitor(monitor, [:flush])
        state = %{state | batches: batches}

        cond do
          generation != state.generation -> {:ok, state}
          outcome == :ok -> {:ok, state |> complete(partition) |> run(hooks)}
          true -> {:send_failed, state}
        end
    end
  end

  @doc """
  Handles a batch process that went down without reporting. Returns
  `{:ignored, state}` when the monitor is not one of the runner's batches.
  """
  @spec down(map(), reference(), term(), map()) :: {:ok | :send_failed | :ignored, map()}
  def down(state, monitor, reason, hooks) do
    case Enum.find(state.batches, fn {_tag, batch} -> batch.monitor == monitor end) do
      nil ->
        {:ignored, state}

      {tag, %{partition: partition, generation: generation}} ->
        state = %{state | batches: Map.delete(state.batches, tag)}

        if generation == state.generation do
          require Logger

          Logger.warning(
            "#{hooks.kind} batch for partition #{inspect(partition)} exited: #{inspect(reason)}"
          )

          # The result was never sent; the stream is reopened so the kernel redelivers.
          {:send_failed, state}
        else
          {:ok, state}
        end
    end
  end

  @doc """
  Forgets everything queued and in flight. Batches still running finish, but
  their results are ignored: they belong to a stream that is gone, and the
  kernel redelivers their events on the new one.
  """
  @spec reset(map()) :: map()
  def reset(state) do
    %{
      state
      | scheduler: PartitionScheduler.reset(state.scheduler),
        generation: state.generation + 1
    }
  end

  defp enqueue(state, entry),
    do: %{state | scheduler: PartitionScheduler.enqueue(state.scheduler, entry)}

  defp complete(state, partition),
    do: %{state | scheduler: PartitionScheduler.complete(state.scheduler, partition)}

  defp run(state, hooks) do
    {actions, scheduler} = PartitionScheduler.schedule(state.scheduler)
    state = %{state | scheduler: scheduler}

    state =
      Enum.reduce(actions, state, fn
        {:run, item}, state ->
          hooks.notify.(state, item)
          state

        {:start, partition, {message, received_at}}, state ->
          start(state, partition, message, received_at, hooks)
      end)

    emit_queue(state, hooks)
    state
  end

  defp start(state, partition, message, received_at, hooks) do
    handler = self()
    tag = make_ref()
    snapshot = state

    {_pid, monitor} =
      spawn_monitor(fn ->
        send(
          handler,
          {:batch_finished, tag, execute(snapshot, partition, message, received_at, hooks)}
        )
      end)

    batch = %{monitor: monitor, partition: partition, generation: state.generation}
    %{state | batches: Map.put(state.batches, tag, batch)}
  end

  defp execute(state, partition, message, received_at, hooks) do
    result =
      case expired(message, received_at) do
        {:expired, waited} ->
          :telemetry.execute(
            [:chronicle, :observer, :batch, :expired],
            %{waited: waited},
            metadata(state, partition, message, hooks)
          )

          hooks.expired_result.(message, @expired_message)

        :in_time ->
          :telemetry.span(
            [:chronicle, :observer, :batch],
            metadata(state, partition, message, hooks),
            fn ->
              result = hooks.build_result.(state, message)
              {result, metadata(state, partition, message, hooks)}
            end
          )
      end

    case ResultSender.send_result(state.stream, result, state.module, state.send_fun) do
      :ok -> :ok
      {:error, reason} -> {:send_failed, reason}
    end
  end

  # The kernel says how long it waits for the result, counted from receipt.
  # Zero (or a kernel that does not send the field) means it waits without a
  # deadline.
  defp expired(message, received_at) do
    case Map.get(message, :DeliverWithinMilliseconds, 0) do
      within when is_integer(within) and within > 0 ->
        waited = System.monotonic_time(:millisecond) - received_at
        if waited >= within, do: {:expired, waited}, else: :in_time

      _ ->
        :in_time
    end
  end

  defp metadata(state, partition, message, hooks) do
    %{
      observer: state.module,
      kind: hooks.kind,
      partition: partition,
      batch_size: length(Map.get(message, :Events, []) || [])
    }
  end

  defp emit_queue(state, hooks) do
    :telemetry.execute(
      [:chronicle, :observer, :queue],
      %{
        queue_depth: PartitionScheduler.queue_depth(state.scheduler),
        in_flight: PartitionScheduler.in_flight(state.scheduler)
      },
      %{observer: state.module, kind: hooks.kind}
    )
  end
end
