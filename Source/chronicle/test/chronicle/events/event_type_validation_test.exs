# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventTypeValidationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.EventTypes

  defmodule OpenedA do
    use Chronicle.Events.EventType, id: "validation-opened", generation: 1
    defstruct account: ""
  end

  defmodule OpenedB do
    use Chronicle.Events.EventType, id: "validation-opened", generation: 1
    defstruct account: ""
  end

  defmodule OpenedV2 do
    use Chronicle.Events.EventType, id: "validation-opened", generation: 2
    defstruct account: ""
  end

  defmodule OtherMigrationV1 do
    use Chronicle.Events.EventType, id: "validation-other", generation: 1
    defstruct []
  end

  defmodule OtherMigrationV2 do
    use Chronicle.Events.EventType, id: "validation-other", generation: 2
    defstruct []
  end

  defmodule OtherMigration do
    use Chronicle.Events.Migration,
      from: {OtherMigrationV1, generation: 1},
      to: {OtherMigrationV2, generation: 2}

    def upcast(builder), do: builder
    def downcast(builder), do: builder
  end

  defmodule DuplicateOtherMigration do
    use Chronicle.Events.Migration,
      from: {OtherMigrationV1, generation: 1},
      to: {OtherMigrationV2, generation: 2}

    def upcast(builder), do: builder
    def downcast(builder), do: builder
  end

  describe "EventTypes.validate!/2" do
    test "passes for a set with no duplicates" do
      assert :ok = EventTypes.validate!([OpenedA, OpenedV2], [])
    end

    test "raises when two modules represent the same generation of the same event type id" do
      assert_raise Chronicle.Events.MultipleEventTypesWithSameIdFound, fn ->
        EventTypes.validate!([OpenedA, OpenedB], [])
      end
    end

    test "raises when more than one migrator bridges the same pair of generations" do
      assert_raise Chronicle.Events.MultipleMigratorsForSameEventTypeGeneration, fn ->
        EventTypes.validate!([OtherMigrationV1, OtherMigrationV2], [
          OtherMigration,
          DuplicateOtherMigration
        ])
      end
    end
  end

  describe "EventTypes.validate/2" do
    test "returns :ok for a set with no duplicates" do
      assert :ok = EventTypes.validate([OpenedA, OpenedV2], [])
    end

    test "returns the duplicate event type exception without raising" do
      assert {:error, %Chronicle.Events.MultipleEventTypesWithSameIdFound{}} =
               EventTypes.validate([OpenedA, OpenedB], [])
    end

    test "returns the duplicate migrator exception without raising" do
      assert {:error, %Chronicle.Events.MultipleMigratorsForSameEventTypeGeneration{}} =
               EventTypes.validate([OtherMigrationV1, OtherMigrationV2], [
                 OtherMigration,
                 DuplicateOtherMigration
               ])
    end
  end

  describe "client startup validation" do
    import ExUnit.CaptureLog

    defp client_opts(strict?) do
      name = :"validation_client_#{System.unique_integer([:positive])}"
      on_exit(fn -> :persistent_term.erase({Chronicle.Client, name}) end)

      [
        name: name,
        discover: false,
        connection_string: "chronicle://u:p@localhost:1",
        event_types: [OpenedA, OpenedB],
        drift_policy: :ignore
      ] ++ if(strict?, do: [strict_validation: true], else: [])
    end

    test "logs the error and continues by default" do
      log =
        capture_log(fn ->
          assert {:ok, _} = Chronicle.Client.init(client_opts(false))
        end)

      assert log =~ "validation-opened"
    end

    test "raises with strict_validation: true" do
      assert_raise Chronicle.Events.MultipleEventTypesWithSameIdFound, fn ->
        Chronicle.Client.init(client_opts(true))
      end
    end
  end
end
