# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.ExpressionShorthandTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  test ":occurred maps to the event context property the kernel understands" do
    assert Coordinator.build_properties(set: [changed_at: :occurred]) ==
             %{"changed_at" => "$eventContext(Occurred)"}
  end

  test "the legacy $occurred string is translated instead of being rejected by the kernel" do
    assert Coordinator.build_properties(set: [changed_at: "$occurred"]) ==
             %{"changed_at" => "$eventContext(Occurred)"}
  end

  test "event context paths and the event source id keep working" do
    assert Coordinator.build_properties(
             set: [id: :event_source_id, seen: "$eventContext(SequenceNumber)"]
           ) == %{"id" => "$eventSourceId", "seen" => "$eventContext(SequenceNumber)"}
  end

  test "a field named id is passed through unchanged" do
    assert Coordinator.build_properties(set: [id: :account_id]) == %{"id" => "accountId"}
  end
end
