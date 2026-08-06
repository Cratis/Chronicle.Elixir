# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EventLogTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventSequences.EventLog

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "event-log-test-some-event"
    defstruct [:value]
  end

  defmodule SomeReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule SomeReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule SomeReducer do
    use Chronicle.Reducers.Reducer, model: SomeReadModel

    @handles SomeEvent

    @impl true
    def reduce(%SomeEvent{}, model, _context), do: model
  end

  defmodule NotAnObserver do
    defstruct []
  end

  describe "observer_event_types/1" do
    test "returns a reactor module's @handles event types" do
      assert EventLog.observer_event_types(SomeReactor) == [SomeEvent]
    end

    test "returns a reducer module's @handles event types" do
      assert EventLog.observer_event_types(SomeReducer) == [SomeEvent]
    end

    test "returns an empty list for a module that is neither a reactor nor a reducer" do
      assert EventLog.observer_event_types(NotAnObserver) == []
    end
  end

  describe "decode_complete_stream_error/1" do
    test "decodes the default-stream-cannot-be-completed wire error" do
      assert EventLog.decode_complete_stream_error(:DefaultStreamCannotBeCompleted) ==
               :default_stream_cannot_be_completed
    end

    test "decodes any other wire error as already_completed" do
      assert EventLog.decode_complete_stream_error(:SomethingElse) == :already_completed
      assert EventLog.decode_complete_stream_error(nil) == :already_completed
    end
  end
end
