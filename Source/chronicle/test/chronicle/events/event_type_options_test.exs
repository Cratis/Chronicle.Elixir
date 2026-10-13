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
end
