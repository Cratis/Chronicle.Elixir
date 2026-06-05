# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ConstraintsTest do
  use ExUnit.Case, async: true

  defmodule UserRegistered do
    use Chronicle.EventType, id: "user-registered-v1"
    defstruct [:email]

    @unique :email
  end

  defmodule AccountCreated do
    use Chronicle.EventType, id: "account-created-v1"
    defstruct [:email, :tenant_id]

    unique [:email, :tenant_id], name: "email_per_tenant"
  end

  defmodule UserDeleted do
    use Chronicle.EventType, id: "user-deleted-v1"
    defstruct [:email]

    @remove_constraint "email_per_tenant"
  end

  defmodule AccountOpened do
    use Chronicle.EventType, id: "account-opened-v1"
    defstruct [:account_id]

    unique_event_type()
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
      constraints = Chronicle.Constraints.from_event_types([UserRegistered])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email",
                 event_definitions: [%{event_type: UserRegistered, on: ["email"]}]
               }
             ]
    end

    test "supports explicit names and removal event mapping" do
      constraints = Chronicle.Constraints.from_event_types([AccountCreated, UserDeleted])

      assert constraints == [
               %{
                 type: :unique,
                 name: "email_per_tenant",
                 event_definitions: [%{event_type: AccountCreated, on: ["email", "tenant_id"]}],
                 removed_with_event_type: UserDeleted
               }
             ]
    end

    test "builds unique event type constraints" do
      constraints = Chronicle.Constraints.from_event_types([AccountOpened])

      assert constraints == [
              %{
                type: :unique_event_type,
                name: "account-opened-v1",
                event_type_id: "account-opened-v1"
              }
             ]
    end
  end
end
