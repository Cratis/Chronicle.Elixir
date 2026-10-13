# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.AppendResult do
  @moduledoc """
  The detailed outcome of an append, mirroring the .NET client's `AppendResult` /
  `AppendManyResult`.

  Returned by `Chronicle.EventSequences.EventLog.append_with_result/3` and
  `append_many_with_result/3`, which return `{:ok, result}` when the append succeeded and
  `{:error, result}` when the kernel rejected it - so a rejection can be inspected instead of
  being collapsed into an opaque term.

    * `:sequence_numbers` - the sequence numbers assigned to the appended events, in order
      (empty when nothing was appended or the kernel did not assign any)
    * `:sequence_number` - the first of those, or `nil`
    * `:correlation_id` - the correlation id of the append
    * `:constraint_violations` - list of `t:constraint_violation/0`
    * `:concurrency_violations` - list of `t:concurrency_violation/0`
    * `:errors` - list of error messages
  """

  alias Chronicle.Events.EventContext

  @unavailable 18_446_744_073_709_551_615

  defstruct success?: false,
            sequence_numbers: [],
            sequence_number: nil,
            correlation_id: "",
            constraint_violations: [],
            concurrency_violations: [],
            errors: [],
            event_sequence_id: "event-log",
            client: Chronicle.Client,
            namespace: nil

  @type constraint_violation :: %{
          constraint_name: String.t(),
          message: String.t(),
          event_type_id: String.t(),
          sequence_number: non_neg_integer(),
          details: %{optional(String.t()) => String.t()}
        }

  @type concurrency_violation :: %{
          event_source_id: String.t(),
          expected_sequence_number: non_neg_integer(),
          actual_sequence_number: non_neg_integer()
        }

  @type t :: %__MODULE__{
          success?: boolean(),
          sequence_numbers: [non_neg_integer()],
          sequence_number: non_neg_integer() | nil,
          correlation_id: String.t(),
          constraint_violations: [constraint_violation()],
          concurrency_violations: [concurrency_violation()],
          errors: [String.t()],
          event_sequence_id: String.t(),
          client: atom(),
          namespace: String.t() | nil
        }

  @doc false
  @spec from_response(map(), keyword()) :: t()
  def from_response(response, opts \\ []) when is_map(response) do
    numbers =
      case field(response, :SequenceNumbers, :sequence_numbers, nil) do
        list when is_list(list) -> list
        _ -> List.wrap(field(response, :SequenceNumber, :sequence_number, nil))
      end
      |> Enum.reject(&(is_nil(&1) or &1 == @unavailable))

    violations =
      List.wrap(field(response, :ConcurrencyViolations, :concurrency_violations, [])) ++
        List.wrap(field(response, :ConcurrencyViolation, :concurrency_violation, nil))

    %__MODULE__{
      success?: field(response, :IsSuccess, :is_success, false) == true,
      sequence_numbers: numbers,
      sequence_number: List.first(numbers),
      correlation_id: correlation(field(response, :CorrelationId, :correlation_id, nil)),
      constraint_violations:
        response
        |> field(:ConstraintViolations, :constraint_violations, [])
        |> List.wrap()
        |> Enum.map(&constraint_violation/1),
      concurrency_violations:
        violations |> Enum.reject(&is_nil/1) |> Enum.map(&concurrency_violation/1),
      errors: response |> field(:Errors, :errors, []) |> List.wrap(),
      event_sequence_id: Keyword.get(opts, :event_sequence_id, "event-log"),
      client: Keyword.get(opts, :client, Chronicle.Client),
      namespace: Keyword.get(opts, :namespace)
    }
  end

  @doc """
  Waits for every observer affected by the appended events to reach the last appended
  sequence number or fail. Mirrors .NET's `AppendResult.WaitForCompletion()`.

  Options: `:timeout` (milliseconds).
  Returns `{:ok, %{success: boolean(), failed_partitions: [...]}}`.
  """
  @spec wait_for_completion(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def wait_for_completion(%__MODULE__{success?: true, sequence_numbers: []}, _opts),
    do: {:ok, %{success: true, failed_partitions: []}}

  def wait_for_completion(%__MODULE__{success?: true} = result, opts) do
    Chronicle.EventSequences.EventLog.wait_for_sequence_number(
      List.last(result.sequence_numbers),
      Keyword.merge(
        [
          client: result.client,
          namespace: result.namespace,
          event_sequence_id: result.event_sequence_id
        ],
        opts
      )
    )
  end

  def wait_for_completion(%__MODULE__{}, _opts), do: {:error, :append_was_not_successful}

  @doc "The `Chronicle.Events.EventContext`-free helper: whether any violation was reported."
  @spec rejected?(t()) :: boolean()
  def rejected?(%__MODULE__{} = result) do
    result.constraint_violations != [] or result.concurrency_violations != [] or
      result.errors != []
  end

  defp constraint_violation(violation) do
    %{
      constraint_name: field(violation, :ConstraintName, :constraint_name, ""),
      message: field(violation, :Message, :message, ""),
      event_type_id: field(violation, :EventTypeId, :event_type_id, ""),
      sequence_number: field(violation, :SequenceNumber, :sequence_number, 0),
      details: violation |> field(:Details, :details, %{}) |> Map.new()
    }
  end

  defp concurrency_violation(violation) do
    %{
      event_source_id: field(violation, :EventSourceId, :event_source_id, ""),
      expected_sequence_number:
        field(violation, :ExpectedSequenceNumber, :expected_sequence_number, 0),
      actual_sequence_number: field(violation, :ActualSequenceNumber, :actual_sequence_number, 0)
    }
  end

  defp correlation(nil), do: ""
  defp correlation(value), do: EventContext.from_wire(%{CorrelationId: value}).correlation_id

  defp field(response, wire_name, name, default),
    do: Map.get(response, wire_name, Map.get(response, name, default))
end
