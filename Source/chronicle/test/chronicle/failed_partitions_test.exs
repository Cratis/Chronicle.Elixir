# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.FailedPartitionsTest do
  use ExUnit.Case, async: true

  alias Chronicle.FailedPartitions
  alias Chronicle.FailedPartitions.{Attempt, FailedPartition}

  describe "decode_failed_partition/1" do
    test "decodes a wire failed partition, including its attempts" do
      wire = %{
        Id: %{Value: "11111111-1111-1111-1111-111111111111"},
        ObserverId: "my-reactor",
        Partition: "account-1",
        Attempts: [
          %{
            Occurred: %{Value: "2026-01-01T00:00:00Z"},
            SequenceNumber: 4,
            Messages: ["boom"],
            StackTrace: "at ..."
          }
        ]
      }

      assert %FailedPartition{
               id: "11111111-1111-1111-1111-111111111111",
               observer_id: "my-reactor",
               partition: "account-1",
               attempts: [
                 %Attempt{
                   sequence_number: 4,
                   messages: ["boom"],
                   stack_trace: "at ...",
                   occurred: %DateTime{}
                 }
               ]
             } = FailedPartitions.decode_failed_partition(wire)
    end

    test "decodes a failed partition with no attempts" do
      wire = %{Id: nil, ObserverId: "my-reactor", Partition: "account-1", Attempts: []}

      assert %FailedPartition{id: nil, attempts: []} =
               FailedPartitions.decode_failed_partition(wire)
    end
  end
end
