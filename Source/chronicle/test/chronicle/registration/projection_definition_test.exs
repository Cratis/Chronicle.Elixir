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

  defmodule DictionaryIncrementReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, event_counts: %{}
    from(SomeEvent, set: [id: :event_source_id])
    from_every(increment: [event_counts: {:event_context, :type}])
  end

  defmodule DictionaryDecrementReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, event_stats: %{}
    from(SomeEvent, set: [id: :event_source_id])
    from_every(decrement: [event_stats: {:event_context, :type}])
  end

  defmodule SimplIncrementReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, counter: 0
    from(SomeEvent, set: [id: :event_source_id])
    from_every(increment: [counter: 1])
  end

  defmodule SimpleDecrementReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, balance: 100
    from(SomeEvent, set: [id: :event_source_id])
    from_every(decrement: [balance: 1])
  end

  defmodule MixedDictionaryOperationsReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, increments: %{}, decrements: %{}, occurred: nil
    from(SomeEvent, set: [id: :event_source_id])
    from_every(increment: [increments: {:event_context, :type}])
    from_every(decrement: [decrements: {:event_context, :type}])
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

    test "increment with event context key produces the correct dictionary key format" do
      definition = Coordinator.build_projection_definition(DictionaryIncrementReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["event_counts.$eventContext.type"] == "$increment"
    end

    test "decrement with event context key produces the correct dictionary key format" do
      definition = Coordinator.build_projection_definition(DictionaryDecrementReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["event_stats.$eventContext.type"] == "$decrement"
    end

    test "increment without event context uses simple field name" do
      definition = Coordinator.build_projection_definition(SimplIncrementReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["counter"] == "$increment"
    end

    test "decrement without event context uses simple field name" do
      definition = Coordinator.build_projection_definition(SimpleDecrementReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["balance"] == "$decrement"
    end

    test "multiple from_every with mixed operations accumulate correctly" do
      definition = Coordinator.build_projection_definition(MixedDictionaryOperationsReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["increments.$eventContext.type"] == "$increment"
      assert properties["decrements.$eventContext.type"] == "$decrement"
      assert properties["occurred"] == "$occurred"
      assert map_size(properties) == 3
    end

    test "dictionary key format matches Chronicle kernel expectations exactly" do
      definition = Coordinator.build_projection_definition(DictionaryIncrementReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      # The kernel expects the exact format: "fieldName.$eventContext.propertyName"
      assert Map.has_key?(properties, "event_counts.$eventContext.type")
      assert properties["event_counts.$eventContext.type"] == "$increment"

      # Verify the FromEveryDefinition structure matches the protobuf contract
      from_every_def = Map.get(definition, :All)
      assert is_struct(from_every_def, Cratis.Chronicle.Contracts.Projections.FromEveryDefinition)
      assert is_map(Map.get(from_every_def, :Properties))
    end

    test "can use different event context properties for dictionary keys" do
      # Test that we can use other event context properties besides :type
      defmodule CorrelationKeyedReadModel do
        use Chronicle.ReadModels.ReadModel
        defstruct id: nil, correlation_stats: %{}
        from(SomeEvent, set: [id: :event_source_id])
        from_every(increment: [correlation_stats: {:event_context, :correlation_id}])
      end

      definition = Coordinator.build_projection_definition(CorrelationKeyedReadModel)
      properties = Map.get(Map.get(definition, :All), :Properties)

      assert properties["correlation_stats.$eventContext.correlation_id"] == "$increment"
    end
  end
end
