# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionSettlement do
  @moduledoc false

  # Settles each partition of a delivery from the problems the functions of an observer
  # reported for it. A partition with no problem succeeds at its last event. Otherwise it
  # settles at the earliest problem: the events before it count as handled, and the problem's
  # state (failed or deferred) applies from it.

  alias Chronicle.Observers.PartitionFailedInBatch

  @typedoc "A failure or deferral at an event of a partition."
  @type problem :: %{
          partition: String.t(),
          at: non_neg_integer(),
          state: :failed | :deferred,
          messages: [String.t()],
          stack_trace: String.t(),
          retry_after: non_neg_integer()
        }

  @typedoc "How a partition of a delivery settled."
  @type outcome :: %{
          partition: String.t(),
          state: :success | :failed | :deferred,
          last_successful_observation: non_neg_integer(),
          messages: [String.t()],
          stack_trace: String.t(),
          retry_after: non_neg_integer(),
          read_model_state: String.t()
        }

  @doc "A failure of `partition` at the event with sequence number `at`."
  @spec failed(String.t(), non_neg_integer(), term()) :: problem()
  def failed(partition, at, reason) do
    %{
      partition: partition,
      at: at,
      state: :failed,
      messages: [inspect(reason)],
      stack_trace: format_stack_trace(reason),
      retry_after: 0
    }
  end

  @doc "A deferral of `partition` at the event with sequence number `at`."
  @spec deferred(String.t(), non_neg_integer(), non_neg_integer()) :: problem()
  def deferred(partition, at, retry_after) do
    %{
      partition: partition,
      at: at,
      state: :deferred,
      messages: [],
      stack_trace: "",
      retry_after: retry_after
    }
  end

  @doc "Turns an outcome a batch function reported into a problem."
  @spec from_batch_outcome(Chronicle.Observers.EventBatch.outcome()) :: problem()
  def from_batch_outcome(%{kind: :deferred} = outcome),
    do: deferred(outcome.partition, outcome.at, outcome.retry_after)

  def from_batch_outcome(%{kind: :failed, reason: nil} = outcome),
    do:
      failed(
        outcome.partition,
        outcome.at,
        PartitionFailedInBatch.exception(partition: outcome.partition)
      )

  def from_batch_outcome(%{kind: :failed} = outcome),
    do: failed(outcome.partition, outcome.at, outcome.reason)

  @doc """
  Settles `partition`, whose events have `sequence_numbers` in order, from every problem
  reported for any partition.
  """
  @spec settle(String.t(), [non_neg_integer()], [problem()]) :: outcome()
  def settle(partition, sequence_numbers, problems) do
    earliest =
      problems
      |> Enum.filter(&(&1.partition == partition))
      |> Enum.min_by(& &1.at, fn -> nil end)

    case earliest do
      nil ->
        outcome(partition, :success, List.last(sequence_numbers) || 0)

      problem ->
        handled = Enum.filter(sequence_numbers, &(&1 < problem.at))

        %{
          outcome(partition, problem.state, List.last(handled) || 0)
          | messages: problem.messages,
            stack_trace: problem.stack_trace,
            retry_after: problem.retry_after
        }
    end
  end

  @doc "An outcome for `partition` with no messages."
  @spec outcome(String.t(), :success | :failed | :deferred, non_neg_integer()) :: outcome()
  def outcome(partition, state, last_successful_observation) do
    %{
      partition: partition,
      state: state,
      last_successful_observation: last_successful_observation,
      messages: [],
      stack_trace: "",
      retry_after: 0,
      read_model_state: ""
    }
  end

  @doc "The wire value of an observation state: Success = 1, Failed = 2, Deferred = 3."
  @spec encode_state(:success | :failed | :deferred) :: 1 | 2 | 3
  def encode_state(:success), do: 1
  def encode_state(:failed), do: 2
  def encode_state(:deferred), do: 3

  @doc """
  Builds the wire `PartitionResult` (of the given contracts module) for an outcome.
  """
  @spec partition_result(module(), outcome()) :: struct()
  def partition_result(module, outcome) do
    struct(module,
      Partition: outcome.partition,
      State: encode_state(outcome.state),
      LastSuccessfulObservation: outcome.last_successful_observation,
      ExceptionMessages: outcome.messages,
      ExceptionStackTrace: outcome.stack_trace,
      RetryAfterMilliseconds: outcome.retry_after,
      ReadModelState: outcome.read_model_state
    )
  end

  @doc """
  The state to report in a legacy single-partition result. A kernel that sends one partition
  does not understand deferrals, so a deferral (which the client never produces then) is
  reported as a failure.
  """
  @spec legacy_state(outcome()) :: 1 | 2
  def legacy_state(%{state: :deferred}), do: encode_state(:failed)
  def legacy_state(%{state: state}), do: encode_state(state)

  @doc false
  def format_stack_trace(%{__exception__: true} = exception), do: Exception.message(exception)
  def format_stack_trace(reason), do: inspect(reason)
end
