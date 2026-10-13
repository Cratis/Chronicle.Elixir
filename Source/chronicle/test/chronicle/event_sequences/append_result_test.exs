# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.AppendResultTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.AppendResult
  alias Chronicle.Events.ConcurrencyScope

  test "a successful single append exposes the assigned sequence number" do
    result = AppendResult.from_response(%{IsSuccess: true, SequenceNumber: 7})

    assert result.success?
    assert result.sequence_number == 7
    assert result.sequence_numbers == [7]
    refute AppendResult.rejected?(result)
  end

  test "a batch exposes all sequence numbers in order" do
    result = AppendResult.from_response(%{IsSuccess: true, SequenceNumbers: [4, 5, 6]})
    assert result.sequence_numbers == [4, 5, 6]
    assert result.sequence_number == 4
  end

  test "the unavailable sentinel is not reported as a sequence number" do
    result =
      AppendResult.from_response(%{IsSuccess: true, SequenceNumber: 18_446_744_073_709_551_615})

    assert result.sequence_numbers == []
    assert result.sequence_number == nil
  end

  test "constraint violations are structured" do
    result =
      AppendResult.from_response(%{
        IsSuccess: false,
        ConstraintViolations: [
          %{
            ConstraintName: "unique-email",
            Message: "Email taken",
            EventTypeId: "registered",
            SequenceNumber: 3,
            Details: %{"email" => "a@b.c"}
          }
        ]
      })

    refute result.success?
    assert AppendResult.rejected?(result)

    assert [
             %{
               constraint_name: "unique-email",
               message: "Email taken",
               details: %{"email" => "a@b.c"}
             }
           ] =
             result.constraint_violations
  end

  test "concurrency violations are structured, from the single and the repeated field" do
    violation = %{EventSourceId: "e1", ExpectedSequenceNumber: 2, ActualSequenceNumber: 5}

    single = AppendResult.from_response(%{ConcurrencyViolation: violation})
    many = AppendResult.from_response(%{ConcurrencyViolations: [violation]})

    expected = [%{event_source_id: "e1", expected_sequence_number: 2, actual_sequence_number: 5}]
    assert single.concurrency_violations == expected
    assert many.concurrency_violations == expected
  end

  test "errors are carried as messages" do
    assert AppendResult.from_response(%{Errors: ["boom"]}).errors == ["boom"]
  end

  describe "ConcurrencyScope.expecting_no_matching_event/1" do
    test "asserts absence explicitly rather than leaving the number unset" do
      scope =
        ConcurrencyScope.expecting_no_matching_event(
          event_source_id: true,
          event_types: [__MODULE__]
        )

      assert scope.expects_no_matching_event
      assert scope.event_source_id
      refute ConcurrencyScope.none().expects_no_matching_event
    end

    test "survives normalization" do
      scope = ConcurrencyScope.expecting_no_matching_event() |> ConcurrencyScope.normalize()
      assert scope.expects_no_matching_event
    end
  end
end
