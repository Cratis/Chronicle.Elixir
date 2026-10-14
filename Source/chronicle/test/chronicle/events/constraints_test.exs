# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ConstraintsTest do
  use ExUnit.Case, async: true

  defmodule UserRegistered do
    use Chronicle.Events.EventType, id: "user-registered-v1"
    defstruct [:email]

    @unique :email
  end

  defmodule AccountCreated do
    use Chronicle.Events.EventType, id: "account-created-v1"
    defstruct [:email, :tenant_id]

    unique([:email, :tenant_id], name: "email_per_tenant")
  end

  defmodule CaseInsensitiveEmailSet do
    use Chronicle.Events.EventType, id: "case-insensitive-email-set-v1"
    defstruct [:email]

    unique(:email, ignore_casing: true, name: "email")
  end

  defmodule UserDeleted do
    use Chronicle.Events.EventType, id: "user-deleted-v1"
    defstruct [:email]

    @remove_constraint "email_per_tenant"
  end

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "account-opened-v1"
    defstruct [:account_id]

    unique_event_type()
  end

  defmodule EmailChanged do
    use Chronicle.Events.EventType, id: "email-changed-v1"
    defstruct [:email]

    unique(:email, name: "email_taken", message: "Email is already taken")
  end

  defmodule SubscriptionStarted do
    use Chronicle.Events.EventType, id: "subscription-started-v1"
    defstruct [:account_id]

    unique_event_type(name: "one-subscription-per-account", message: "Already subscribed")
  end

  defmodule UsernameClaimed do
    use Chronicle.Events.EventType, id: "username-claimed-v1"
    defstruct [:username]

    unique(:username, name: "username_per_source_type", scope: :per_event_source_type)
  end

  defmodule SlotReserved do
    use Chronicle.Events.EventType, id: "slot-reserved-v1"
    defstruct [:slot]

    unique(:slot,
      name: "slot_per_stream",
      scope: [:per_event_stream_type, :per_event_stream_id]
    )
  end

  describe "from_event_types/1" do
    test "captures options from unique/2 macro" do
      assert AccountCreated.__chronicle_event_type__(:constraints) == %{
               unique: [{[:email, :tenant_id], [name: "email_per_tenant"]}],
               unique_event_type: [],
               remove_constraint: []
             }
    end

    test "builds unique constraints from event type attributes" do
      constraints = Chronicle.Events.Constraints.from_event_types([UserRegistered])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email",
                 ignore_casing: false,
                 event_definitions: [%{event_type: UserRegistered, on: ["email"]}]
               }
             ]
    end

    test "supports case-insensitive unique constraints" do
      constraints = Chronicle.Events.Constraints.from_event_types([CaseInsensitiveEmailSet])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email",
                 ignore_casing: true,
                 event_definitions: [%{event_type: CaseInsensitiveEmailSet, on: ["email"]}]
               }
             ]
    end

    test "supports explicit names and removal event mapping" do
      constraints = Chronicle.Events.Constraints.from_event_types([AccountCreated, UserDeleted])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email_per_tenant",
                 ignore_casing: false,
                 event_definitions: [%{event_type: AccountCreated, on: ["email", "tenant_id"]}],
                 removed_with_event_types: [UserDeleted]
               }
             ]
    end

    test "builds unique event type constraints" do
      constraints = Chronicle.Events.Constraints.from_event_types([AccountOpened])

      assert constraints == [
               %{
                 type: :unique_event_type,
                 name: "account-opened-v1",
                 event_type_ids: ["account-opened-v1"]
               }
             ]
    end

    test "does not drop a :message declared on unique/2" do
      constraints = Chronicle.Events.Constraints.from_event_types([EmailChanged])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email_taken",
                 ignore_casing: false,
                 message: "Email is already taken",
                 event_definitions: [%{event_type: EmailChanged, on: ["email"]}]
               }
             ]
    end

    test "does not drop a :message declared on unique_event_type/1" do
      constraints = Chronicle.Events.Constraints.from_event_types([SubscriptionStarted])

      assert constraints == [
               %{
                 type: :unique_event_type,
                 name: "one-subscription-per-account",
                 event_type_ids: ["subscription-started-v1"],
                 message: "Already subscribed"
               }
             ]
    end

    test "captures a single :scope dimension" do
      constraints = Chronicle.Events.Constraints.from_event_types([UsernameClaimed])

      assert constraints == [
               %{
                 type: :unique,
                 name: "username_per_source_type",
                 ignore_casing: false,
                 scope: [:per_event_source_type],
                 event_definitions: [%{event_type: UsernameClaimed, on: ["username"]}]
               }
             ]
    end

    test "captures multiple :scope dimensions" do
      constraints = Chronicle.Events.Constraints.from_event_types([SlotReserved])

      assert [%{scope: scope}] = constraints
      assert Enum.sort(scope) == [:per_event_stream_id, :per_event_stream_type]
    end

    test "does not set :scope when none was declared" do
      constraints = Chronicle.Events.Constraints.from_event_types([UserRegistered])

      assert [definition] = constraints
      refute Map.has_key?(definition, :scope)
    end
  end

  describe "build_constraint/1" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    test "carries a custom unique constraint message alongside the wire Constraint" do
      [definition] = Constraints.from_event_types([EmailChanged])

      assert {%Constraint{} = wire_constraint, message} = Constraints.build_constraint(definition)

      # The message travels alongside the wire struct rather than on it: the
      # generated Constraint has no field for it, matching the C#, TypeScript
      # and Kotlin reference clients, none of which send a constraint message
      # to the kernel at registration time.
      assert message == "Email is already taken"
      assert Map.get(wire_constraint, :Name) == "email_taken"
      assert Map.get(wire_constraint, :Type) == :Unique
      refute Map.has_key?(Map.from_struct(wire_constraint), :Message)
    end

    test "carries a custom unique_event_type constraint message alongside the wire Constraint" do
      [definition] = Constraints.from_event_types([SubscriptionStarted])

      assert {%Constraint{} = wire_constraint, message} = Constraints.build_constraint(definition)

      assert message == "Already subscribed"
      assert Map.get(wire_constraint, :Name) == "one-subscription-per-account"
      assert Map.get(wire_constraint, :Type) == :UniqueEventType
    end

    test "defaults the message to an empty string when none was declared" do
      [definition] = Constraints.from_event_types([UserRegistered])

      assert {%Constraint{}, ""} = Constraints.build_constraint(definition)
    end

    test "leaves Scope unset when no :scope was declared" do
      [definition] = Constraints.from_event_types([UserRegistered])

      assert {%Constraint{Scope: nil}, _message} = Constraints.build_constraint(definition)
    end

    test "sets only the scoped dimension's field on the wire ConstraintScope" do
      [definition] = Constraints.from_event_types([UsernameClaimed])

      assert {%Constraint{Scope: scope}, _message} = Constraints.build_constraint(definition)

      assert Map.get(scope, :EventSourceType) == "_scoped_"
      assert Map.get(scope, :EventStreamType) == ""
      assert Map.get(scope, :EventStreamId) == ""
    end

    test "sets every scoped dimension's field on the wire ConstraintScope" do
      [definition] = Constraints.from_event_types([SlotReserved])

      assert {%Constraint{Scope: scope}, _message} = Constraints.build_constraint(definition)

      assert Map.get(scope, :EventStreamType) == "_scoped_"
      assert Map.get(scope, :EventStreamId) == "_scoped_"
      assert Map.get(scope, :EventSourceType) == ""
    end
  end

  describe "removal events on the wire" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    defmodule WireEmailRegistered do
      use Chronicle.Events.EventType, id: "constraints-wire-email-registered"
      defstruct email: ""
      unique(:email, name: "WireEmail")
    end

    defmodule WireEmailReleased do
      use Chronicle.Events.EventType, id: "constraints-wire-email-released"
      defstruct []
      remove_constraint("WireEmail")
    end

    defmodule WireAccountClosed do
      use Chronicle.Events.EventType, id: "constraints-wire-account-closed"
      defstruct []
      remove_constraint("WireEmail")
    end

    test "sends every releasing event type as a list the contract can encode" do
      [definition] =
        Constraints.from_event_types([WireEmailRegistered, WireEmailReleased, WireAccountClosed])

      {%Constraint{RemovedWith: removed_with} = wire, _message} =
        Constraints.build_constraint(definition)

      assert Enum.sort(removed_with) == [
               "constraints-wire-account-closed",
               "constraints-wire-email-released"
             ]

      assert byte_size(Constraint.encode(wire)) > 0
    end

    test "sends an empty list when nothing releases the constraint" do
      [definition] = Constraints.from_event_types([WireEmailRegistered])

      assert {%Constraint{RemovedWith: []}, _message} = Constraints.build_constraint(definition)
    end
  end

  describe "unique properties on the wire" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    defmodule WireOwnerEmailSet do
      use Chronicle.Events.EventType, id: "constraints-wire-owner-email-set"
      defstruct owner_email: ""
      unique(:owner_email)
    end

    test "names multi-word properties the way the event is serialized, keeping the constraint name" do
      [definition] = Constraints.from_event_types([WireOwnerEmailSet])

      {%Constraint{Name: name, Definition: definition}, _message} =
        Constraints.build_constraint(definition)

      assert name == "owner_email"
      assert [%{Properties: ["ownerEmail"]}] = definition."Value0"."EventDefinitions"
    end
  end

  describe "unique_event_type on the wire" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    defmodule WireLoanCheckedOut do
      use Chronicle.Events.EventType, id: "constraints-wire-loan-checked-out"
      defstruct []
      unique_event_type(name: "WireOneOpenLoan", scope: :per_event_stream_id)
    end

    defmodule WireLoanReturned do
      use Chronicle.Events.EventType, id: "constraints-wire-loan-returned"
      defstruct []
      remove_constraint("WireOneOpenLoan")
    end

    test "sends every event type id as the repeated EventTypeIds field, not the dropped singular EventTypeId" do
      [definition] = Constraints.from_event_types([WireLoanCheckedOut])

      {%Constraint{Definition: definition}, _message} = Constraints.build_constraint(definition)

      assert definition."Value1"."EventTypeIds" == ["constraints-wire-loan-checked-out"]
    end

    test "sets the scoped dimension on the wire ConstraintScope" do
      [definition] = Constraints.from_event_types([WireLoanCheckedOut])

      {%Constraint{Scope: scope}, _message} = Constraints.build_constraint(definition)

      assert Map.get(scope, :EventStreamId) == "_scoped_"
    end

    test "carries the releasing event type in RemovedWith" do
      [definition] = Constraints.from_event_types([WireLoanCheckedOut, WireLoanReturned])

      {%Constraint{RemovedWith: removed_with}, _message} =
        Constraints.build_constraint(definition)

      assert removed_with == ["constraints-wire-loan-returned"]
    end

    defmodule WirePersonAliasedTo do
      use Chronicle.Events.EventType, id: "constraints-wire-person-aliased-to"
      defstruct []
      unique_event_type(name: "WirePersonTerminal")
    end

    defmodule WirePersonErased do
      use Chronicle.Events.EventType, id: "constraints-wire-person-erased"
      defstruct []
      unique_event_type(name: "WirePersonTerminal")
    end

    test "merges unique_event_type declarations sharing a name into one constraint with every event type id" do
      constraints = Constraints.from_event_types([WirePersonAliasedTo, WirePersonErased])

      assert [%{type: :unique_event_type, name: "WirePersonTerminal"} = definition] = constraints

      assert Enum.sort(definition.event_type_ids) ==
               Enum.sort(["constraints-wire-person-aliased-to", "constraints-wire-person-erased"])
    end
  end

  describe "unique_event_type event_sequences" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    defmodule EventSequencedUniqueEventType do
      use Chronicle.Events.EventType, id: "constraints-event-sequenced-unique-event-type"
      defstruct []
      unique_event_type(name: "SequencedOneOpen", event_sequences: "outbox")
    end

    test "restricts the declaration to the declared event sequences" do
      [definition] = Constraints.from_event_types([EventSequencedUniqueEventType])
      assert definition.event_sequences == ["outbox"]

      {%Constraint{EventSequences: event_sequences}, _message} =
        Constraints.build_constraint(definition)

      assert event_sequences == ["outbox"]
    end
  end

  describe "removal event definitions (per-value removal properties)" do
    alias Chronicle.Events.Constraints
    alias Cratis.Chronicle.Contracts.Events.Constraints.Constraint

    defmodule MappingVersionRegistered do
      use Chronicle.Events.EventType, id: "constraints-mapping-version-registered"
      defstruct version_id: ""
      unique(:version_id, name: "UniqueMappingVersionId", mode: :per_value)
    end

    defmodule MappingVersionRemoved do
      use Chronicle.Events.EventType, id: "constraints-mapping-version-removed"
      defstruct version_id: ""
      remove_constraint("UniqueMappingVersionId", properties: [:version_id])
    end

    defmodule MappingVersionsRemoved do
      use Chronicle.Events.EventType, id: "constraints-mapping-versions-removed"
      defstruct []
      remove_constraint("UniqueMappingVersionId")
    end

    test "carries the releasing event's properties as a RemovalEventDefinition" do
      [definition] =
        Constraints.from_event_types([
          MappingVersionRegistered,
          MappingVersionRemoved,
          MappingVersionsRemoved
        ])

      assert definition.removal_event_definitions == [
               %{event_type: MappingVersionRemoved, on: ["version_id"]}
             ]

      assert Enum.sort(definition.removed_with_event_types) ==
               Enum.sort([MappingVersionRemoved, MappingVersionsRemoved])

      {%Constraint{Definition: wire_definition}, _message} =
        Constraints.build_constraint(definition)

      assert [%{Properties: ["versionId"]}] = wire_definition."Value0"."RemovalEventDefinitions"
    end

    test "a bare remove_constraint/1 contributes no RemovalEventDefinitions" do
      [definition] =
        Constraints.from_event_types([MappingVersionRegistered, MappingVersionsRemoved])

      refute Map.has_key?(definition, :removal_event_definitions)
    end
  end

  describe "message callback" do
    alias Chronicle.Events.Constraints

    defmodule MessageCallbackChecker do
      def message_for(_violation), do: "computed"
    end

    defmodule CallbackMessageProjectCreated do
      use Chronicle.Events.EventType, id: "constraints-callback-message-project-created"
      defstruct name: ""

      unique(:name,
        name: "CallbackMessageProjectName",
        message: {Chronicle.ConstraintsTest.MessageCallbackChecker, :message_for}
      )
    end

    test "keeps a {Module, :function} message callback intact through from_event_types and build_constraint" do
      [definition] = Constraints.from_event_types([CallbackMessageProjectCreated])

      assert definition.message ==
               {Chronicle.ConstraintsTest.MessageCallbackChecker, :message_for}

      assert {_wire_constraint, {Chronicle.ConstraintsTest.MessageCallbackChecker, :message_for}} =
               Constraints.build_constraint(definition)
    end
  end
end
