# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventTypeTest do
  use ExUnit.Case, async: true

  defmodule TestEvent do
    use Chronicle.Events.EventType, id: "test-event-v1"
    defstruct [:field_a, :field_b]
  end

  defmodule TestEventWithGeneration do
    use Chronicle.Events.EventType, id: "test-event-gen", generation: 3
    defstruct [:data]
  end

  defmodule TestEventWithConstraints do
    use Chronicle.Events.EventType, id: "test-event-constraints"
    defstruct [:email]

    @unique :email
    unique_event_type()
    @remove_constraint :email
  end

  describe "use Chronicle.Events.EventType" do
    test "exposes event type id" do
      assert TestEvent.__chronicle_event_type__(:id) == "test-event-v1"
    end

    test "defaults generation to 1" do
      assert TestEvent.__chronicle_event_type__(:generation) == 1
    end

    test "exposes explicit generation" do
      assert TestEventWithGeneration.__chronicle_event_type__(:generation) == 3
    end

    test "implements Chronicle.Events.EventType behaviour" do
      assert function_exported?(TestEvent, :__chronicle_event_type__, 1)
    end

    test "exposes declared constraints" do
      assert TestEventWithConstraints.__chronicle_event_type__(:constraints) == %{
               unique: [:email],
               unique_event_type: [[]],
               remove_constraint: [:email]
             }
    end
  end

  defmodule NotAnEventType do
    defstruct [:value]
  end

  describe "event_type?/1" do
    test "is true for a module that uses Chronicle.Events.EventType" do
      assert Chronicle.Events.EventType.event_type?(TestEvent)
    end

    test "is false for an ordinary struct module" do
      refute Chronicle.Events.EventType.event_type?(NotAnEventType)
    end

    test "is false for a module that does not exist" do
      refute Chronicle.Events.EventType.event_type?(NotALoadedModule)
    end

    test "is false for a non-module value" do
      refute Chronicle.Events.EventType.event_type?("not-a-module")
    end
  end
end
