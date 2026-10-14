# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReactorTest do
  use ExUnit.Case, async: true

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule AnotherEvent do
    use Chronicle.Events.EventType, id: "another-event"
    defstruct [:count]
  end

  defmodule TestReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent
    @handles AnotherEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
    def handle(%AnotherEvent{}, _context), do: :ok
  end

  defmodule NamedReactor do
    use Chronicle.Reactors.Reactor, id: "my-custom-reactor-id"

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule PinnedReactor do
    use Chronicle.Reactors.Reactor, generation_delivery: :pinned

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  describe "use Chronicle.Reactors.Reactor" do
    test "accumulates @handles event types" do
      handles = TestReactor.__chronicle_reactor__(:handles)
      assert SomeEvent in handles
      assert AnotherEvent in handles
    end

    test "defaults id to module name" do
      assert TestReactor.__chronicle_reactor__(:id) == to_string(TestReactor)
    end

    test "supports explicit id" do
      assert NamedReactor.__chronicle_reactor__(:id) == "my-custom-reactor-id"
    end

    test "implements Chronicle.Reactors.Reactor behaviour" do
      assert function_exported?(TestReactor, :handle, 2)
    end

    test "defaults generation_delivery to unset (client default applies)" do
      assert TestReactor.__chronicle_reactor__(:generation_delivery) == nil
    end

    test "supports an explicit generation_delivery option" do
      assert PinnedReactor.__chronicle_reactor__(:generation_delivery) == :pinned
    end
  end
end
