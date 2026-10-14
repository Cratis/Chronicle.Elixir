# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventTypeOptionsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.{EventTypes, Migrators}

  defmodule Opened do
    use Chronicle.Events.EventType, id: "options-opened"
    defstruct account: ""
  end

  defmodule Closed do
    use Chronicle.Events.EventType, id: "options-closed", tombstone: true, public: true
    defstruct account: ""
  end

  defmodule OpenedInError do
    use Chronicle.Events.EventType, id: "options-opened-in-error", compensation_for: Opened
    defstruct account: ""
  end

  defmodule OpenedV2 do
    use Chronicle.Events.EventType, id: "options-opened-gen", generation: 2
    defstruct account: ""
  end

  defmodule OpenedV1 do
    use Chronicle.Events.EventType, generation_for: OpenedV2, generation: 1
    defstruct account: ""
  end

  defp registration(module),
    do: EventTypes.build_registration([module], "store", Migrators.new([]))

  test "defaults: not a tombstone, visibility left to the kernel" do
    registration = registration(Opened)
    refute Map.fetch!(Map.fetch!(registration, :Type), :Tombstone)
    assert Map.fetch!(registration, :Visibility) == :Unspecified

    refute registration
           |> Map.fetch!(:Schema)
           |> Jason.decode!()
           |> Map.has_key?("compensationFor")
  end

  test "tombstone and public are registered" do
    registration = registration(Closed)
    assert Map.fetch!(Map.fetch!(registration, :Type), :Tombstone)
    assert Map.fetch!(registration, :Visibility) == :Public
  end

  test "compensation_for writes the compensationFor schema extension" do
    schema = registration(OpenedInError) |> Map.fetch!(:Schema) |> Jason.decode!()
    assert schema["compensationFor"] == "options-opened"
    assert schema["properties"]["account"]["type"] == "string"
  end

  describe "generation_for:" do
    test "resolves the id from the target module and keeps its own generation" do
      assert OpenedV1.__chronicle_event_type__(:id) == "options-opened-gen"
      assert OpenedV1.__chronicle_event_type__(:generation) == 1
      assert OpenedV1.__chronicle_event_type__(:generation_for) == OpenedV2
    end

    test "a plain event type has no generation_for" do
      assert Opened.__chronicle_event_type__(:generation_for) == nil
    end

    test "groups with its target under the same event type registration" do
      registrations =
        [OpenedV1, OpenedV2]
        |> Enum.uniq()
        |> Enum.group_by(& &1.__chronicle_event_type__(:id))
        |> Enum.map(fn {_id, modules} ->
          EventTypes.build_registration(modules, "store", Migrators.new([]))
        end)

      assert [registration] = registrations
      assert Map.fetch!(Map.fetch!(registration, :Type), :Id) == "options-opened-gen"

      generations =
        registration |> Map.fetch!(:Generations) |> Enum.map(&Map.fetch!(&1, :Generation))

      assert Enum.sort(generations) == [1, 2]
    end

    test "raises when :id is also given" do
      assert_raise Chronicle.Events.EventTypeGenerationForCannotBeCombinedWithEventType, fn ->
        Code.compile_string("""
        defmodule Chronicle.Events.EventTypeOptionsTest.BothIdAndGenerationFor do
          defmodule V2 do
            use Chronicle.Events.EventType, id: "both-v2"
            defstruct [:a]
          end

          defmodule V1 do
            use Chronicle.Events.EventType, id: "both-v1", generation_for: V2, generation: 1
            defstruct [:a]
          end
        end
        """)
      end
    end

    test "raises when :generation is missing" do
      assert_raise ArgumentError, fn ->
        Code.compile_string("""
        defmodule Chronicle.Events.EventTypeOptionsTest.MissingGeneration do
          defmodule V2 do
            use Chronicle.Events.EventType, id: "missing-gen-v2"
            defstruct [:a]
          end

          defmodule V1 do
            use Chronicle.Events.EventType, generation_for: V2
            defstruct [:a]
          end
        end
        """)
      end
    end

    test "raises when the target does not use Chronicle.Events.EventType" do
      assert_raise Chronicle.Events.EventTypeGenerationReferencesNonEventType, fn ->
        Code.compile_string("""
        defmodule Chronicle.Events.EventTypeOptionsTest.NonEventTypeTarget do
          defmodule NotAnEventType do
            defstruct [:a]
          end

          defmodule V1 do
            use Chronicle.Events.EventType,
              generation_for: Chronicle.Events.EventTypeOptionsTest.NonEventTypeTarget.NotAnEventType,
              generation: 1

            defstruct [:a]
          end
        end
        """)
      end
    end
  end
end
