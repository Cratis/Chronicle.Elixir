# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.SeederTest do
  use ExUnit.Case, async: true

  defmodule SomeEvent do
    use Chronicle.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule AnotherEvent do
    use Chronicle.EventType, id: "another-event"
    defstruct [:count]
  end

  defmodule TestSeeder do
    use Chronicle.Seeder

    @impl true
    def seed(builder) do
      builder
      |> Chronicle.Seeding.for(SomeEvent, "source-1", [
        %SomeEvent{value: "test"}
      ])
    end
  end

  defmodule NamedSeeder do
    use Chronicle.Seeder, id: "my-custom-seeder-id"

    @impl true
    def seed(builder) do
      builder
    end
  end

  defmodule MultiEventSeeder do
    use Chronicle.Seeder

    @impl true
    def seed(builder) do
      builder
      |> Chronicle.Seeding.for_event_source("source-2", [
        %SomeEvent{value: "multi"},
        %AnotherEvent{count: 42}
      ])
    end
  end

  describe "use Chronicle.Seeder" do
    test "defines __chronicle_seeder__/1 function" do
      assert function_exported?(TestSeeder, :__chronicle_seeder__, 1)
    end

    test "defaults id to module name" do
      assert TestSeeder.__chronicle_seeder__(:id) == to_string(TestSeeder)
    end

    test "supports explicit id" do
      assert NamedSeeder.__chronicle_seeder__(:id) == "my-custom-seeder-id"
    end

    test "implements Chronicle.Seeder behaviour" do
      assert function_exported?(TestSeeder, :seed, 1)
    end
  end

  describe "Chronicle.Seeding.discover/2" do
    test "invokes seeders and accumulates entries" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result = Chronicle.Seeding.discover(builder, [TestSeeder])

      assert length(result.entries) == 1
      assert hd(result.entries).event_source_id == "source-1"
      assert hd(result.entries).event.__struct__ == SomeEvent
    end

    test "handles multiple seeders" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result = Chronicle.Seeding.discover(builder, [TestSeeder, MultiEventSeeder])

      assert length(result.entries) == 3
    end

    test "continues on seeder failure" do
      defmodule FailingSeeder do
        use Chronicle.Seeder

        @impl true
        def seed(_builder) do
          raise "intentional failure"
        end
      end

      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      # Should not raise, should log warning and continue
      result = Chronicle.Seeding.discover(builder, [FailingSeeder, TestSeeder])

      # TestSeeder should still have added its entry
      assert length(result.entries) == 1
    end
  end

  describe "Chronicle.Seeding.for/4" do
    test "adds events for a specific type" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result =
        Chronicle.Seeding.for(builder, SomeEvent, "source-1", [
          %SomeEvent{value: "first"},
          %SomeEvent{value: "second"}
        ])

      assert length(result.entries) == 2
      assert Enum.all?(result.entries, &(&1.event_source_id == "source-1"))
      assert Enum.all?(result.entries, &(&1.event.__struct__ == SomeEvent))
      assert Enum.all?(result.entries, &(&1.is_global == true))
    end
  end

  describe "Chronicle.Seeding.for_event_source/3" do
    test "adds multiple event types for same source" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result =
        Chronicle.Seeding.for_event_source(builder, "source-1", [
          %SomeEvent{value: "test"},
          %AnotherEvent{count: 42}
        ])

      assert length(result.entries) == 2
      assert Enum.all?(result.entries, &(&1.event_source_id == "source-1"))
      assert Enum.at(result.entries, 0).event.__struct__ == SomeEvent
      assert Enum.at(result.entries, 1).event.__struct__ == AnotherEvent
    end
  end

  describe "Chronicle.Seeding.for_namespace/3" do
    test "scopes events to specific namespace" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result =
        Chronicle.Seeding.for_namespace(builder, "production", fn scoped ->
          Chronicle.Seeding.for(scoped, SomeEvent, "source-1", [
            %SomeEvent{value: "namespaced"}
          ])
        end)

      assert length(result.entries) == 1
      entry = hd(result.entries)
      assert entry.is_global == false
      assert entry.target_namespace == "production"
    end

    test "preserves global entries when adding namespaced" do
      builder = %Chronicle.Seeding{
        entries: [],
        event_types: Chronicle.EventTypes,
        connection: :test_connection,
        event_store: "test",
        namespace: "default"
      }

      result =
        builder
        |> Chronicle.Seeding.for(SomeEvent, "source-1", [%SomeEvent{value: "global"}])
        |> Chronicle.Seeding.for_namespace("production", fn scoped ->
          Chronicle.Seeding.for(scoped, SomeEvent, "source-2", [
            %SomeEvent{value: "namespaced"}
          ])
        end)

      assert length(result.entries) == 2
      global_entries = Enum.filter(result.entries, & &1.is_global)
      namespaced_entries = Enum.reject(result.entries, & &1.is_global)

      assert length(global_entries) == 1
      assert length(namespaced_entries) == 1
    end
  end
end
