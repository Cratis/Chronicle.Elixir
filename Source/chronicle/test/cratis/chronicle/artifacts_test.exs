# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Artifacts

  defmodule DiscoveredEvent do
    use Cratis.Chronicle.Events.EventType, id: "discovered-event"
    defstruct [:value]
  end

  defmodule DiscoveredReadModel do
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule DiscoveredReactor do
    use Cratis.Chronicle.Reactors.Reactor

    @handles DiscoveredEvent

    @impl true
    def handle(%DiscoveredEvent{}, _context), do: :ok
  end

  defmodule DiscoveredReducer do
    use Cratis.Chronicle.Reducers.Reducer, model: DiscoveredReadModel

    @handles DiscoveredEvent

    @impl true
    def reduce(%DiscoveredEvent{} = event, _model, _context),
      do: %DiscoveredReadModel{total: event.value}
  end

  defmodule DiscoveredSeeder do
    use Cratis.Chronicle.Seeding.Seeder

    @impl true
    def seed(builder), do: builder
  end

  defmodule DiscoveredCaptureEvent do
    use Cratis.Chronicle.Events.EventType, id: "DiscoveredCaptureEvent"
    defstruct [:value]
  end

  defmodule DiscoveredCapture do
    use Cratis.Chronicle.Captures.Capture, name: "DiscoveredCapture"
    webhook_source("/discovered")
    key("id")

    append DiscoveredCaptureEvent, when: :added do
      set(:value, "$.value")
    end
  end

  describe "discover_loaded/0" do
    test "categorizes loaded artifacts by their introspection functions" do
      discovered = Artifacts.discover_loaded()

      assert DiscoveredEvent in discovered.event_types
      assert DiscoveredReactor in discovered.reactors
      assert DiscoveredReducer in discovered.reducers
      assert DiscoveredReadModel in discovered.read_models
      assert DiscoveredSeeder in discovered.seeders
      assert DiscoveredCapture in discovered.captures
    end

    test "returns a map with every artifact category" do
      discovered = Artifacts.discover_loaded()

      assert Map.keys(discovered) |> Enum.sort() ==
               [
                 :captures,
                 :constraints,
                 :event_sources,
                 :event_store_subscriptions,
                 :event_types,
                 :global_handlers,
                 :graphs,
                 :migrations,
                 :projections,
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
      assert discovered.captures == []
    end
  end

  describe "report/1" do
    test "builds a Cratis.Chronicle.Discovery.Report, leaving discover/1's map shape untouched" do
      report = Artifacts.report(:nonexistent_app)

      assert %Cratis.Chronicle.Discovery.Report{has_run: true, artifacts: []} = report
      assert is_map(Artifacts.discover(:nonexistent_app))
    end
  end
end
