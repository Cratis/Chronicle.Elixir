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

  defmodule MultiWordEvent do
    use Chronicle.Events.EventType, id: "projection-definition-test-multi-word-event"
    defstruct owner_name: "", initial_balance: 0, name: "", account_id: ""
  end

  defmodule ExplicitMultiWordReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, owner: nil, balance: 0, on_loan: false, rate: 0.0

    from(MultiWordEvent,
      set: [id: :event_source_id, owner: :owner_name, on_loan: true, rate: 1.5],
      add: [balance: :initial_balance]
    )
  end

  defmodule AutoMappedMultiWordReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, owner_name: nil, initial_balance: 0, name: nil
    from(MultiWordEvent, set: [id: :event_source_id])
  end

  defmodule AutoMapExclusionsReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, owner_name: nil, initial_balance: 0
    from(MultiWordEvent, set: [id: :event_source_id, owner_name: "legacyOwner"])
    no_auto_map([:initial_balance])
  end

  defmodule AutoMapDisabledReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, owner_name: nil
    from(MultiWordEvent, set: [id: :event_source_id])
    no_auto_map()
  end

  defmodule MultiWordJoinReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, owner_name: nil
    from(SomeEvent, set: [id: :event_source_id])
    join(MultiWordEvent, on: :account_id, key: :account_id)
  end

  defmodule DepartmentRenamed do
    use Chronicle.Events.EventType, id: "projection-definition-test-department-renamed"
    defstruct display_name: "", department_id: ""
  end

  defmodule AggregateOnlyMultiWordReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct owner_name: nil, initial_balance: 0
    from(MultiWordEvent, add: [initial_balance: :initial_balance])
  end

  defmodule RedirectedJoinReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, display_name: nil, department_name: nil, department_id: nil
    from(SomeEvent, set: [id: :event_source_id])
    join(DepartmentRenamed, on: :department_id, set: [department_name: :display_name])
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

  describe "event field expressions" do
    defp from_properties(read_model, event) do
      read_model
      |> Coordinator.build_projection_definition()
      |> Map.get(:From)
      |> Enum.find(&(Map.get(Map.get(&1, :Key), :Id) == event.__chronicle_event_type__(:id)))
      |> Map.get(:Value)
      |> Map.get(:Properties)
    end

    test "a multi-word event field is read by its camelCase wire name" do
      properties = from_properties(ExplicitMultiWordReadModel, MultiWordEvent)

      assert properties["owner"] == "ownerName"
      assert properties["balance"] == "$add(initialBalance)"
    end

    test "booleans and floats are sent as constants, not field names" do
      properties = from_properties(ExplicitMultiWordReadModel, MultiWordEvent)

      assert properties["on_loan"] == "$value(true)"
      assert properties["rate"] == "$value(1.5)"
    end

    test "multi-word fields shared with the event are mapped the way AutoMap would" do
      properties = from_properties(AutoMappedMultiWordReadModel, MultiWordEvent)

      assert properties["owner_name"] == "ownerName"
      assert properties["initial_balance"] == "initialBalance"
      # Single-word names are left to the kernel's own AutoMap.
      refute Map.has_key?(properties, "name")
    end

    test "explicit mappings and no_auto_map fields are not overridden" do
      properties = from_properties(AutoMapExclusionsReadModel, MultiWordEvent)

      assert properties["owner_name"] == "legacyOwner"
      refute Map.has_key?(properties, "initial_balance")
    end

    test "no_auto_map() adds no multi-word mappings" do
      properties = from_properties(AutoMapDisabledReadModel, MultiWordEvent)

      refute Map.has_key?(properties, "owner_name")
    end

    test "join key is an event field, on is the read model property" do
      join =
        MultiWordJoinReadModel
        |> Coordinator.build_projection_definition()
        |> Map.get(:Join)
        |> hd()
        |> Map.get(:Value)

      assert Map.get(join, :On) == "account_id"
      assert Map.get(join, :Key) == "accountId"
      assert Map.get(join, :Properties)["owner_name"] == "ownerName"
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

  describe "auto map rules shared with the kernel" do
    test "an aggregate-only from gets no automatic mappings" do
      [from] =
        AggregateOnlyMultiWordReadModel
        |> Coordinator.build_projection_definition()
        |> Map.get(:From)

      assert from |> Map.get(:Value) |> Map.get(:Properties) == %{
               "initial_balance" => "$add(initialBalance)"
             }
    end

    test "a join doesn't also map an event field an explicit mapping already reads" do
      [join] =
        RedirectedJoinReadModel |> Coordinator.build_projection_definition() |> Map.get(:Join)

      properties = join |> Map.get(:Value) |> Map.get(:Properties)

      assert properties["department_name"] == "displayName"
      refute Map.has_key?(properties, "display_name")
      assert properties["department_id"] == "departmentId"
    end
  end
end
