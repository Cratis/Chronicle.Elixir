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

  describe "Chronicle.Seeding.register/1" do
    test "appends grouped seed events for sources without existing events" do
      builder =
        base_builder(self())
        |> Chronicle.Seeding.for_event_source("source-1", [
          %SomeEvent{value: "first"},
          %AnotherEvent{count: 2}
        ])
        |> Chronicle.Seeding.for_namespace("production", fn scoped ->
          Chronicle.Seeding.for(scoped, SomeEvent, "source-2", [%SomeEvent{value: "namespaced"}])
        end)

      assert :ok = Chronicle.Seeding.register(builder)

      assert_received {:checked, "source-1", [client: :test_client, namespace: "default"]}
      assert_received {:checked, "source-2", [client: :test_client, namespace: "production"]}

      assert_received {:appended, "source-1", [SomeEvent, AnotherEvent],
                       [client: :test_client, namespace: "default"]}

      assert_received {:appended, "source-2", [SomeEvent],
                       [client: :test_client, namespace: "production"]}
    end

    test "skips appending for sources that already have events" do
      builder =
        base_builder(self(), fn _event_source_id, _opts -> {:ok, true} end)
        |> Chronicle.Seeding.for(SomeEvent, "source-1", [%SomeEvent{value: "existing"}])

      assert :ok = Chronicle.Seeding.register(builder)
      assert_received {:checked, "source-1", [client: :test_client, namespace: "default"]}
      refute_received {:appended, _, _, _}
    end
  end

  defp base_builder(receiver, has_events_for \\ fn _event_source_id, _opts -> {:ok, false} end) do
    %Chronicle.Seeding{
      entries: [],
      event_types: Chronicle.EventTypes,
      connection: :test_connection,
      event_store: "test",
      namespace: "default",
      client: :test_client,
      has_events_for: fn event_source_id, opts ->
        send(receiver, {:checked, event_source_id, opts})
        has_events_for.(event_source_id, opts)
      end,
      append_many: fn event_source_id, events, opts ->
        send(receiver, {:appended, event_source_id, Enum.map(events, & &1.__struct__), opts})
        :ok
      end
    }
  end
end
