# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionSettlementTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.PartitionSettlement

  test "succeeds at the last event when nothing was reported" do
    assert %{state: :success, last_successful_observation: 7} =
             PartitionSettlement.settle("a", [3, 5, 7], [])
  end

  test "settles at the earliest problem reported for the partition" do
    problems = [
      PartitionSettlement.failed("a", 7, :late),
      PartitionSettlement.deferred("a", 5, 100),
      PartitionSettlement.failed("b", 1, :other)
    ]

    assert %{state: :deferred, last_successful_observation: 3, retry_after: 100} =
             PartitionSettlement.settle("a", [3, 5, 7], problems)
  end

  test "counts nothing as handled when the first event failed" do
    assert %{state: :failed, last_successful_observation: 0, messages: [":bad"]} =
             PartitionSettlement.settle("a", [3, 5], [PartitionSettlement.failed("a", 3, :bad)])
  end

  test "reports a deferral as a failure to a kernel that predates pages" do
    outcome = PartitionSettlement.settle("a", [3], [PartitionSettlement.deferred("a", 3, 10)])
    assert PartitionSettlement.legacy_state(outcome) == 2
    assert PartitionSettlement.encode_state(outcome.state) == 3
  end
end
