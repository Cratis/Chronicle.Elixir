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
                 removed_with_event_type: UserDeleted
               }
             ]
    end

    test "builds unique event type constraints" do
      constraints = Chronicle.Events.Constraints.from_event_types([AccountOpened])

      assert constraints == [
               %{
                 type: :unique_event_type,
                 name: "account-opened-v1",
                 event_type_id: "account-opened-v1"
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
                 event_type_id: "subscription-started-v1",
                 message: "Already subscribed"
               }
             ]
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
  end
end
