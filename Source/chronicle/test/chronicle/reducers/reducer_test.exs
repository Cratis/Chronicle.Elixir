# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReducerTest do
  use ExUnit.Case, async: true

  defmodule MyEvent do
    use Chronicle.Events.EventType, id: "my-event"
    defstruct [:amount]
  end

  defmodule MyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule TestReducer do
    use Chronicle.Reducers.Reducer, model: MyReadModel

    @handles MyEvent

    @impl true
    def reduce(%MyEvent{} = event, nil, _context) do
      %MyReadModel{total: event.amount}
    end

    def reduce(%MyEvent{} = event, model, _context) do
      %{model | total: model.total + event.amount}
    end
  end

  defmodule PassiveReducer do
    use Chronicle.Reducers.Reducer, model: MyReadModel, active: false

    @handles MyEvent

    @impl true
    def reduce(%MyEvent{} = event, nil, _context), do: %MyReadModel{total: event.amount}
  end

  describe "use Chronicle.Reducers.Reducer" do
    test "exposes the model module" do
      assert TestReducer.__chronicle_reducer__(:model) == MyReadModel
    end

    test "accumulates @handles event types" do
      assert MyEvent in TestReducer.__chronicle_reducer__(:handles)
    end

    test "defaults id to module name" do
      assert TestReducer.__chronicle_reducer__(:id) == to_string(TestReducer)
    end

    test "defaults active to true" do
      assert TestReducer.__chronicle_reducer__(:active) == true
    end

    test "supports an explicit active: false for a passive reducer" do
      assert PassiveReducer.__chronicle_reducer__(:active) == false
    end

    test "reduce/3 builds initial model" do
      result = TestReducer.reduce(%MyEvent{amount: 100}, nil, %{})
      assert result == %MyReadModel{total: 100}
    end

    test "reduce/3 accumulates state" do
      model = TestReducer.reduce(%MyEvent{amount: 100}, nil, %{})
      result = TestReducer.reduce(%MyEvent{amount: 50}, model, %{})
      assert result == %MyReadModel{total: 150}
    end
  end
end
