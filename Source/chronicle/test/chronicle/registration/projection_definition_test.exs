# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.ProjectionDefinitionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "projection-definition-test-some-event"
    defstruct [:name, :balance]
  end

  defmodule DefaultReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil, balance: 0
    from(SomeEvent, set: [id: :event_source_id, name: :name])
  end

  defmodule NoAutoMapReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil, balance: 0
    from(SomeEvent, set: [id: :event_source_id, name: :name])
    no_auto_map()
  end

  defmodule NoAutoMapFieldsReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil, balance: 0
    from(SomeEvent, set: [id: :event_source_id, name: :name])
    no_auto_map([:balance])
  end

  defmodule NoAutoMapAccumulatedReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil, balance: 0
    from(SomeEvent, set: [id: :event_source_id])
    no_auto_map([:balance])
    no_auto_map([:name])
  end

  defmodule NotRewindableReadModel do
    use Chronicle.ReadModels.ReadModel, not_rewindable: true
    defstruct id: nil, name: nil
    from(SomeEvent, set: [id: :event_source_id, name: :name])
  end

  defmodule CustomSequenceReadModel do
    use Chronicle.ReadModels.ReadModel, event_sequence: "inbox"
    defstruct id: nil, name: nil
    from(SomeEvent, set: [id: :event_source_id, name: :name])
  end

  defmodule MultipleFromEveryReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil, occurred: nil
    from(SomeEvent, set: [id: :event_source_id])
    from_every(set: [name: :name])
    from_every(set: [occurred: :occurred])
  end

  describe "auto map" do
    test "a read model that declares nothing leaves the kernel default in place" do
      definition = Coordinator.build_projection_definition(DefaultReadModel)

      assert Map.get(definition, :AutoMap) == :Inherit
      assert Map.get(definition, :NoAutoMapProperties) == []
    end

    test "no_auto_map disables auto mapping for the whole projection" do
      definition = Coordinator.build_projection_definition(NoAutoMapReadModel)

      assert Map.get(definition, :AutoMap) == :Disabled
      assert Map.get(definition, :NoAutoMapProperties) == []
    end

    test "no_auto_map with fields keeps auto mapping on and excludes just those fields" do
      definition = Coordinator.build_projection_definition(NoAutoMapFieldsReadModel)

      assert Map.get(definition, :AutoMap) == :Enabled
      assert Map.get(definition, :NoAutoMapProperties) == ["balance"]
    end

    test "several no_auto_map declarations accumulate rather than replace" do
      definition = Coordinator.build_projection_definition(NoAutoMapAccumulatedReadModel)

      assert Map.get(definition, :AutoMap) == :Enabled
      assert Map.get(definition, :NoAutoMapProperties) == ["balance", "name"]
    end
  end

  describe "rewindable" do
    test "a read model is rewindable by default" do
      assert Map.get(Coordinator.build_projection_definition(DefaultReadModel), :IsRewindable)
    end

    test "not_rewindable: true makes the projection non-rewindable" do
      refute Map.get(
               Coordinator.build_projection_definition(NotRewindableReadModel),
               :IsRewindable
             )
    end
  end

  describe "event sequence" do
    test "a read model observes the event log by default" do
      assert Map.get(Coordinator.build_projection_definition(DefaultReadModel), :EventSequenceId) ==
               "event-log"
    end

    test "event_sequence points the projection at another sequence" do
      assert Map.get(
               Coordinator.build_projection_definition(CustomSequenceReadModel),
               :EventSequenceId
             ) ==
               "inbox"
    end
  end

  describe "from_every" do
    test "every declaration contributes its mappings rather than only the first" do
      definition = Coordinator.build_projection_definition(MultipleFromEveryReadModel)

      assert Map.keys(Map.get(Map.get(definition, :All), :Properties)) |> Enum.sort() == [
               "name",
               "occurred"
             ]
    end
  end
end
