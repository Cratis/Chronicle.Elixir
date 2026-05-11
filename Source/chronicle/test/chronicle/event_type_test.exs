# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventTypeTest do
  use ExUnit.Case, async: true

  defmodule TestEvent do
    use Chronicle.EventType, id: "test-event-v1"
    defstruct [:field_a, :field_b]
  end

  defmodule TestEventWithGeneration do
    use Chronicle.EventType, id: "test-event-gen", generation: 3
    defstruct [:data]
  end

  describe "use Chronicle.EventType" do
    test "exposes event type id" do
      assert TestEvent.__chronicle_event_type__(:id) == "test-event-v1"
    end

    test "defaults generation to 1" do
      assert TestEvent.__chronicle_event_type__(:generation) == 1
    end

    test "exposes explicit generation" do
      assert TestEventWithGeneration.__chronicle_event_type__(:generation) == 3
    end

    test "implements Chronicle.EventType behaviour" do
      assert function_exported?(TestEvent, :__chronicle_event_type__, 1)
    end
  end
end
