# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConstraintTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.Constraints

  defmodule UserRegistered do
    use Chronicle.Events.EventType, id: "constraint-module-user-registered"
    defstruct email: ""
  end

  defmodule UserEmailChanged do
    use Chronicle.Events.EventType, id: "constraint-module-user-email-changed"
    defstruct new_email: ""
  end

  defmodule UserRemoved do
    use Chronicle.Events.EventType, id: "constraint-module-user-removed"
    defstruct []
  end

  defmodule UniqueEmail do
    use Chronicle.Events.Constraint

    unique name: "ConstraintModuleUniqueEmail" do
      on(UserRegistered, [:email])
      on(UserEmailChanged, [:new_email])
      removed_with(UserRemoved)
    end
  end

  defmodule LoanCheckedOut do
    use Chronicle.Events.EventType, id: "constraint-module-loan-checked-out"
    defstruct []
  end

  defmodule LoanReturned do
    use Chronicle.Events.EventType, id: "constraint-module-loan-returned"
    defstruct []
  end

  defmodule OneOpenLoan do
    use Chronicle.Events.Constraint

    unique_event_type(LoanCheckedOut, name: "ConstraintModuleOneOpenLoan")
    removed_with(LoanReturned)
  end

  defmodule PersonAliasedTo do
    use Chronicle.Events.EventType, id: "constraint-module-person-aliased-to"
    defstruct []
  end

  defmodule PersonErased do
    use Chronicle.Events.EventType, id: "constraint-module-person-erased"
    defstruct []
  end

  defmodule PersonTerminalOutcome do
    use Chronicle.Events.Constraint

    unique_event_type(PersonAliasedTo, name: "ConstraintModulePersonTerminal")
    unique_event_type(PersonErased, name: "ConstraintModulePersonTerminal")
  end

  defmodule MappingVersionRegistered do
    use Chronicle.Events.EventType, id: "constraint-module-mapping-version-registered"
    defstruct version_id: ""
  end

  defmodule MappingVersionRemoved do
    use Chronicle.Events.EventType, id: "constraint-module-mapping-version-removed"
    defstruct version_id: ""
  end

  defmodule PerValueMappingVersion do
    use Chronicle.Events.Constraint

    unique name: "ConstraintModulePerValue", mode: :per_value do
      on(MappingVersionRegistered, [:version_id])
      removed_with(MappingVersionRemoved, properties: [:version_id])
    end
  end

  describe "unique/2 with on/2" do
    test "combines several event types under one constraint name" do
      [definition] = UniqueEmail.__chronicle_constraint__(:definitions)

      assert definition.type == :unique
      assert definition.name == "ConstraintModuleUniqueEmail"

      assert definition.event_definitions == [
               %{event_type: UserRegistered, on: ["email"]},
               %{event_type: UserEmailChanged, on: ["new_email"]}
             ]

      assert definition.removed_with_event_types == [UserRemoved]
    end

    test "is accepted by Constraints.from_constraint_modules/1 and builds on the wire" do
      [definition] = Constraints.from_constraint_modules([UniqueEmail])
      {wire_constraint, _message} = Constraints.build_constraint(definition)

      assert Map.get(wire_constraint, :Name) == "ConstraintModuleUniqueEmail"
      assert Map.get(wire_constraint, :Type) == :Unique
    end

    test "mode defaults to per_event_source" do
      [definition] = UniqueEmail.__chronicle_constraint__(:definitions)
      refute Map.has_key?(definition, :mode)
    end

    test "per_value mode and removal properties produce a RemovalEventDefinition" do
      [definition] = PerValueMappingVersion.__chronicle_constraint__(:definitions)

      assert definition.mode == :per_value
      assert definition.removed_with_event_types == [MappingVersionRemoved]

      assert definition.removal_event_definitions == [
               %{event_type: MappingVersionRemoved, on: ["version_id"]}
             ]
    end
  end

  describe "unique_event_type/1,2" do
    test "resolves event type ids lazily when __chronicle_constraint__(:definitions) is called" do
      [definition] = OneOpenLoan.__chronicle_constraint__(:definitions)

      assert definition.type == :unique_event_type
      assert definition.name == "ConstraintModuleOneOpenLoan"
      assert definition.event_type_ids == ["constraint-module-loan-checked-out"]
      assert definition.removed_with_event_types == [LoanReturned]
    end

    test "merges declarations sharing a name into one mutually-exclusive constraint" do
      [definition] = PersonTerminalOutcome.__chronicle_constraint__(:definitions)

      assert definition.name == "ConstraintModulePersonTerminal"

      assert Enum.sort(definition.event_type_ids) ==
               Enum.sort([
                 "constraint-module-person-aliased-to",
                 "constraint-module-person-erased"
               ])
    end
  end

  describe "Chronicle.Artifacts discovery" do
    test "discovers loaded constraint modules" do
      discovered = Chronicle.Artifacts.discover_loaded()
      assert UniqueEmail in discovered.constraints
      assert OneOpenLoan in discovered.constraints
    end
  end

  describe "compile-time validation" do
    test "requires an explicit :name for unique/2" do
      assert_raise ArgumentError, ~r/requires an explicit :name/, fn ->
        compile("""
        unique [] do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        end
        """)
      end
    end

    test "requires an explicit :name for unique_event_type/1,2" do
      assert_raise ArgumentError, ~r/requires an explicit :name/, fn ->
        compile("""
        unique_event_type Chronicle.Events.ConstraintTest.LoanCheckedOut
        """)
      end
    end

    test "rejects an empty on" do
      assert_raise ArgumentError, ~r/has no `on` declaration/, fn ->
        compile("""
        unique name: "Empty" do
        end
        """)
      end
    end

    test "rejects adding the same event type twice to one unique constraint" do
      assert_raise ArgumentError, ~r/added to the same unique constraint more than once/, fn ->
        compile("""
        unique name: "Dup" do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        end
        """)
      end
    end

    test "rejects a name declared more than once" do
      assert_raise ArgumentError, ~r/is declared more than once/, fn ->
        compile("""
        unique name: "SameName" do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        end

        unique_event_type Chronicle.Events.ConstraintTest.LoanCheckedOut, name: "SameName"
        """)
      end
    end

    test "rejects conflicting retention modes under the same name" do
      assert_raise ArgumentError, ~r/conflicting retention modes/, fn ->
        compile("""
        unique name: "ConflictingModes", mode: :per_event_source do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        end

        unique name: "ConflictingModes", mode: :per_value do
          on Chronicle.Events.ConstraintTest.UserEmailChanged, [:new_email]
        end
        """)
      end
    end

    test "rejects an unknown property on an event type" do
      assert_raise ArgumentError, ~r/does not exist on/, fn ->
        compile("""
        unique name: "UnknownProperty" do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:does_not_exist]
        end
        """)
      end
    end

    test "rejects an unknown option" do
      assert_raise ArgumentError, ~r/unknown option/, fn ->
        compile("""
        unique name: "UnknownOption", not_a_real_option: true do
          on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        end
        """)
      end
    end

    test "rejects removed_with before any unique_event_type has been declared" do
      assert_raise ArgumentError, ~r/no unique_event_type\/1,2 has been declared/, fn ->
        compile("""
        removed_with Chronicle.Events.ConstraintTest.LoanReturned
        """)
      end
    end

    test "rejects on/2 called outside a unique do ... end block" do
      assert_raise ArgumentError, ~r/must be called inside/, fn ->
        compile("""
        on Chronicle.Events.ConstraintTest.UserRegistered, [:email]
        """)
      end
    end
  end

  defp compile(body) do
    unique = System.unique_integer([:positive])

    {{:module, module, _binary, _term}, _} =
      Code.eval_string("""
      defmodule Chronicle.Events.ConstraintTest.Compiled#{unique} do
        use Chronicle.Events.Constraint

        #{body}
      end
      """)

    module
  end
end
