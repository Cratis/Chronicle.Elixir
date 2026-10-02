# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.CompositeKeyDefinitionTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator
  alias Cratis.Chronicle.Contracts.Projections.ProjectionDefinition

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "composite-key-definition-test-some-event"
    defstruct [:name, :account_id]
  end

  defmodule WeeklyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct count: 0

    from(SomeEvent,
      key:
        {:composite,
         [
           {"Year", {:event_context, "Occurred.Year"}},
           {"Week", {:event_context, "Occurred.Week"}}
         ]},
      count: :count
    )
  end

  defmodule WeeklyProjection do
    use Chronicle.Projections.Projection, model: WeeklyReadModel

    from(SomeEvent,
      key:
        {:composite,
         [
           {"Year", {:event_context, "Occurred.Year"}},
           {"Week", {:event_context, "Occurred.Week"}}
         ]},
      count: :count
    )
  end

  defmodule MixedKeyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct count: 0

    from(SomeEvent,
      key:
        {:composite,
         [
           account_id: :account_id,
           month: {:event_context, "Occurred.Month"},
           day: {:event_context, "Occurred.Day"},
           source: :event_source_id,
           occurred: :occurred,
           name: "name",
           category: 1,
           active: true
         ]},
      count: :count
    )
  end

  test "a serialized model-bound weekly key matches the .NET composite-key spec" do
    key = WeeklyReadModel |> Coordinator.build_projection_definition() |> serialized_key()

    # Chronicle #4087: and_accessor_is_an_iso_week_derived_function.
    assert key ==
             "$composite(Year=$eventContext(Occurred.Year),Week=$eventContext(Occurred.Week))"
  end

  test "a serialized declarative weekly key matches the .NET composite-key spec" do
    key =
      WeeklyProjection
      |> Coordinator.build_declarative_projection_definition()
      |> serialized_key()

    assert key ==
             "$composite(Year=$eventContext(Occurred.Year),Week=$eventContext(Occurred.Week))"
  end

  test "composite parts preserve target names, expression conventions and list order" do
    key = MixedKeyReadModel |> Coordinator.build_projection_definition() |> serialized_key()

    assert key ==
             "$composite(account_id=accountId,month=$eventContext(Occurred.Month),day=$eventContext(Occurred.Day),source=$eventSourceId,occurred=$occurred,name=name,category=$value(1),active=$value(true))"
  end

  test "existing standalone keys keep their expressions" do
    for {key, expected} <- [
          {:event_source_id, "$eventSourceId"},
          {:occurred, "$occurred"},
          {:account_id, "accountId"},
          {"$composite(legacy=name)", "$composite(legacy=name)"},
          {1, "$value(1)"},
          {true, "$value(true)"}
        ] do
      assert Coordinator.resolve_key_expression(key) == expected
    end
  end

  defp serialized_key(definition) do
    definition = definition |> ProjectionDefinition.encode() |> ProjectionDefinition.decode()
    [from] = Map.get(definition, :From)
    from |> Map.get(:Value) |> Map.get(:Key)
  end
end
