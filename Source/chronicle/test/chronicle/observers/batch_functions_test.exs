# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.BatchFunctionsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.{
    BatchFunctionObservesUnknownEventType,
    BatchFunctions,
    EventTypeObservedByMoreThanOneFunction,
    InvalidBatchFunction,
    ObservesOnlyOnBatchFunctions,
    PerEventCallbackMissing,
    ReducerHasMoreThanOneBatchFunction,
    ReducerMixesBatchAndPerEventFunctions
  }

  defmodule Registered do
    use Chronicle.Events.EventType, id: "batch-functions-registered"
    defstruct [:name]
  end

  defmodule Renamed do
    use Chronicle.Events.EventType, id: "batch-functions-renamed"
    defstruct [:name]
  end

  defmodule EmailChanged do
    use Chronicle.Events.EventType, id: "batch-functions-email-changed"
    defstruct [:email]
  end

  defmodule Model do
    use Chronicle.ReadModels.ReadModel
    defstruct [:name]
  end

  defmodule MixedReactor do
    use Chronicle.Reactors.Reactor

    @handles EmailChanged

    @observes Registered
    @observes Renamed
    def index(batch, _context), do: batch

    @impl true
    def handle(%EmailChanged{}, _context), do: :ok
  end

  defmodule TwoBatchReactor do
    use Chronicle.Reactors.Reactor

    @observes Registered
    def index(_batch, _context), do: :ok

    @observes Renamed
    def audit(_batch, _context), do: :ok
  end

  defmodule BatchReducer do
    use Chronicle.Reducers.Reducer, model: Model

    @observes Registered
    @observes Renamed
    def fold(_batch, current, _context), do: current
  end

  describe "discovering batch functions" do
    test "registers the event types of batch functions and per-event handlers" do
      assert MixedReactor.__chronicle_reactor__(:handles) == [Registered, Renamed, EmailChanged]
      assert MixedReactor.__chronicle_reactor__(:per_event) == [EmailChanged]
    end

    test "pairs each batch function with the event types it observes" do
      assert BatchFunctions.validate!(:reactor, MixedReactor) == %{
               batch: [index: [Registered, Renamed]],
               per_event: [EmailChanged]
             }

      assert BatchFunctions.validate!(:reactor, TwoBatchReactor).batch == [
               index: [Registered],
               audit: [Renamed]
             ]
    end

    test "lets a reducer fold with one batch function" do
      assert BatchFunctions.validate!(:reducer, BatchReducer) == %{
               batch: [fold: [Registered, Renamed]],
               per_event: []
             }

      assert BatchReducer.__chronicle_reducer__(:handles) == [Registered, Renamed]
    end
  end

  describe "refusing an observer whose event types reach more than one function" do
    defmodule ObservedAndHandled do
      use Chronicle.Reactors.Reactor

      @handles Registered

      @observes Registered
      def index(_batch, _context), do: :ok

      @impl true
      def handle(_event, _context), do: :ok
    end

    defmodule ObservedTwice do
      use Chronicle.Reactors.Reactor

      @observes Registered
      def index(_batch, _context), do: :ok

      @observes Registered
      def audit(_batch, _context), do: :ok
    end

    test "an event type observed by a batch function and handled per event" do
      assert_raise EventTypeObservedByMoreThanOneFunction, fn ->
        BatchFunctions.validate!(:reactor, ObservedAndHandled)
      end
    end

    test "an event type observed by two batch functions" do
      assert_raise EventTypeObservedByMoreThanOneFunction, fn ->
        BatchFunctions.validate!(:reactor, ObservedTwice)
      end
    end
  end

  describe "refusing a batch function with the wrong shape" do
    defmodule ObservesOnHandle do
      use Chronicle.Reactors.Reactor

      @observes Registered
      @impl true
      def handle(_event, _context), do: :ok
    end

    defmodule WrongArity do
      use Chronicle.Reactors.Reactor

      @observes Registered
      def index(_batch), do: :ok
    end

    defmodule ObservesSomethingElse do
      use Chronicle.Reactors.Reactor

      @observes String
      def index(_batch, _context), do: :ok
    end

    defmodule HandlesWithoutHandle do
      use Chronicle.Reactors.Reactor

      @handles Registered
    end

    test "@observes on a per-event callback" do
      assert_raise ObservesOnlyOnBatchFunctions, fn ->
        BatchFunctions.validate!(:reactor, ObservesOnHandle)
      end
    end

    test "a reactor batch function that does not take (batch, context)" do
      assert_raise InvalidBatchFunction, fn -> BatchFunctions.validate!(:reactor, WrongArity) end
    end

    test "a batch function observing a module that is not an event type" do
      assert_raise BatchFunctionObservesUnknownEventType, fn ->
        BatchFunctions.validate!(:reactor, ObservesSomethingElse)
      end
    end

    test "per-event event types without handle/2" do
      assert_raise PerEventCallbackMissing, fn ->
        BatchFunctions.validate!(:reactor, HandlesWithoutHandle)
      end
    end
  end

  describe "refusing a reducer that is not a single fold" do
    defmodule MixedReducer do
      use Chronicle.Reducers.Reducer, model: Model

      @handles Renamed

      @observes Registered
      def fold(_batch, current, _context), do: current

      @impl true
      def reduce(_event, current, _context), do: current
    end

    defmodule TwoFoldReducer do
      use Chronicle.Reducers.Reducer, model: Model

      @observes Registered
      def fold(_batch, current, _context), do: current

      @observes Renamed
      def other_fold(_batch, current, _context), do: current
    end

    defmodule ObservesOnReduce do
      use Chronicle.Reducers.Reducer, model: Model

      @observes Registered
      @impl true
      def reduce(_event, current, _context), do: current
    end

    test "a batch function and per-event reduce/3" do
      assert_raise ReducerMixesBatchAndPerEventFunctions, fn ->
        BatchFunctions.validate!(:reducer, MixedReducer)
      end
    end

    test "two batch functions" do
      assert_raise ReducerHasMoreThanOneBatchFunction, fn ->
        BatchFunctions.validate!(:reducer, TwoFoldReducer)
      end
    end

    test "@observes on reduce/3" do
      assert_raise ObservesOnlyOnBatchFunctions, fn ->
        BatchFunctions.validate!(:reducer, ObservesOnReduce)
      end
    end
  end
end
