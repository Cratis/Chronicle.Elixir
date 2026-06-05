# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Artifacts

  defmodule DiscoveredEvent do
    use Chronicle.Events.EventType, id: "discovered-event"
    defstruct [:value]
  end

  defmodule DiscoveredReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule DiscoveredReactor do
    use Chronicle.Reactors.Reactor

    @handles DiscoveredEvent

    @impl true
    def handle(%DiscoveredEvent{}, _context), do: :ok
  end

  defmodule DiscoveredReducer do
    use Chronicle.Reducers.Reducer, model: DiscoveredReadModel

    @handles DiscoveredEvent

    @impl true
    def reduce(%DiscoveredEvent{} = event, _model, _context),
      do: %DiscoveredReadModel{total: event.value}
  end

  defmodule DiscoveredSeeder do
    use Chronicle.Seeding.Seeder

    @impl true
    def seed(builder), do: builder
  end

  describe "discover_loaded/0" do
    test "categorizes loaded artifacts by their introspection functions" do
      discovered = Artifacts.discover_loaded()

      assert DiscoveredEvent in discovered.event_types
      assert DiscoveredReactor in discovered.reactors
      assert DiscoveredReducer in discovered.reducers
      assert DiscoveredReadModel in discovered.read_models
      assert DiscoveredSeeder in discovered.seeders
    end

    test "returns a map with every artifact category" do
      discovered = Artifacts.discover_loaded()

      assert Map.keys(discovered) |> Enum.sort() ==
               [
                 :event_store_subscriptions,
                 :event_types,
                 :migrations,
                 :reactors,
                 :read_models,
                 :reducers,
                 :seeders,
                 :webhooks
               ]
    end
  end

  describe "discover/1" do
    test "returns empty lists for an application with no modules" do
      discovered = Artifacts.discover(:nonexistent_app)

      assert discovered.event_types == []
      assert discovered.reactors == []
      assert discovered.reducers == []
      assert discovered.seeders == []
    end
  end
end
