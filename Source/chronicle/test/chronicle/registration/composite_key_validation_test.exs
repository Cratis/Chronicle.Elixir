# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.CompositeKeyValidationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "composite-key-validation-test-some-event"
    defstruct [:name]
  end

  defmodule InvalidKeyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct count: 0

    from(SomeEvent,
      key: {:composite, [week: {:event_context, :occurred}]},
      count: :count
    )
  end

  defmodule InvalidKeyProjection do
    use Chronicle.Projections.Projection, model: InvalidKeyReadModel

    from(SomeEvent,
      key: {:composite, [week: {:event_context, "Occurred.Week1"}]},
      count: :count
    )
  end

  test "atom event-context key paths raise a clear argument error" do
    error =
      assert_raise ArgumentError, fn ->
        Coordinator.resolve_key_expression({:event_context, :occurred})
      end

    assert error.message =~ "event-context key paths must be strings such as \"Occurred.Week\""
    assert error.message =~ ":occurred"
  end

  test "other non-string event-context paths raise the same clear argument error" do
    for path <- [nil, 1, ["Occurred", "Week"]] do
      error =
        assert_raise ArgumentError, fn ->
          Coordinator.resolve_key_expression({:event_context, path}, InvalidKeyReadModel)
        end

      assert error.message =~ inspect(InvalidKeyReadModel)
      assert error.message =~ "event-context key paths must be strings"
      assert error.message =~ inspect(path)
    end
  end

  test "model-bound key diagnostics identify the read model and offending part" do
    error =
      assert_raise ArgumentError, fn ->
        Coordinator.build_projection_definition(InvalidKeyReadModel)
      end

    assert error.message =~ inspect(InvalidKeyReadModel)
    assert error.message =~ inspect({:week, {:event_context, :occurred}})
    assert error.message =~ "event-context key paths must be strings"
  end

  test "declarative key diagnostics identify the read model and offending part" do
    error =
      assert_raise ArgumentError, fn ->
        Coordinator.build_declarative_projection_definition(InvalidKeyProjection)
      end

    assert error.message =~ inspect(InvalidKeyReadModel)
    assert error.message =~ inspect({:week, {:event_context, "Occurred.Week1"}})
    assert error.message =~ "must contain only letters, dots and parentheses"
  end

  test "empty and non-list composite parts raise argument errors" do
    for parts <- [[], :week, "week", %{week: :name}] do
      error =
        assert_raise ArgumentError, fn ->
          Coordinator.resolve_key_expression({:composite, parts}, InvalidKeyReadModel)
        end

      assert error.message =~ inspect(InvalidKeyReadModel)
      assert error.message =~ "non-empty list of {name, part} pairs"
      assert error.message =~ inspect(parts)
    end
  end

  test "malformed parts and non-string non-atom names raise argument errors" do
    for part <- [:week, {"Week"}, {"Week", :name, :extra}, {1, :name}, {[], :name}] do
      error =
        assert_raise ArgumentError, fn ->
          Coordinator.resolve_key_expression({:composite, [part]}, InvalidKeyReadModel)
        end

      assert error.message =~ inspect(InvalidKeyReadModel)
      assert error.message =~ "{name, part} pairs with string or atom names"
      assert error.message =~ inspect(part)
    end
  end

  test "nested composites raise argument errors naming the offending part" do
    for nested_parts <- [[week: :name], [], :invalid] do
      part = {:week, {:composite, nested_parts}}

      error =
        assert_raise ArgumentError, fn ->
          Coordinator.resolve_key_expression({:composite, [part]}, InvalidKeyReadModel)
        end

      assert error.message =~ inspect(InvalidKeyReadModel)
      assert error.message =~ "nested composite keys are not supported"
      assert error.message =~ inspect(part)
    end
  end

  test "unsupported composite part expressions raise argument errors" do
    part = {:week, {:unknown, "Occurred.Week"}}

    error =
      assert_raise ArgumentError, fn ->
        Coordinator.resolve_key_expression({:composite, [part]}, InvalidKeyReadModel)
      end

    assert error.message =~ inspect(InvalidKeyReadModel)
    assert error.message =~ inspect(part)
    assert error.message =~ "unsupported expression"
  end

  test "event-context paths reject characters outside the kernel regex" do
    for path <- [
          "Occurred.Week1",
          "Occurred.Week_",
          "Occurred.Week,Name",
          "$occurred",
          "Occurred-Week",
          "Occurred Week",
          "Occurred.Wéek",
          "Occurred.Week\n"
        ] do
      part = {:week, {:event_context, path}}

      error =
        assert_raise ArgumentError, fn ->
          Coordinator.resolve_key_expression({:composite, [part]}, InvalidKeyReadModel)
        end

      assert error.message =~ inspect(InvalidKeyReadModel)
      assert error.message =~ inspect(part)
      assert error.message =~ "must contain only letters, dots and parentheses"
    end
  end

  test "event-context paths preserve the kernel's accepted letters dots and parentheses" do
    assert Coordinator.resolve_key_expression(
             {:composite, [{"Week", {:event_context, "Occurred.Week()"}}]},
             InvalidKeyReadModel
           ) == "$composite(Week=$eventContext(Occurred.Week()))"
  end
end
