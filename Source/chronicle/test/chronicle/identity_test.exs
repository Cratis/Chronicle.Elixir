# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.IdentityTest do
  use ExUnit.Case, async: true

  alias Chronicle.{Identity, IdentityProvider}

  describe "Identity" do
    test "new/4 builds identity" do
      identity = Identity.new("user-1", "Alice", "alice")

      assert identity.subject == "user-1"
      assert identity.name == "Alice"
      assert identity.user_name == "alice"
    end

    test "well-known identities have expected sentinel subjects" do
      assert Identity.system().subject == "5d032c92-9d5e-41eb-947a-ee5314ed0032"
      assert Identity.not_set().subject == "1efc9b81-0612-4466-962c-86acc4e9a028"
      assert Identity.unknown().subject == "3321cf62-db16-425e-8173-99fcfefe11dd"
    end

    test "without_duplicates removes duplicate subjects from chain" do
      identity =
        Identity.new(
          "service-a",
          "Service A",
          "service-a",
          Identity.new(
            "service-a",
            "Service A Duplicate",
            "service-a",
            Identity.new("user-1", "User", "user")
          )
        )

      deduped = Identity.without_duplicates(identity)

      assert deduped.subject == "service-a"
      assert deduped.on_behalf_of.subject == "user-1"
      assert deduped.on_behalf_of.on_behalf_of == nil
    end
  end

  describe "IdentityProvider" do
    setup do
      Process.delete({IdentityProvider, :current})
      :ok
    end

    test "returns system identity when no identity set" do
      assert IdentityProvider.get_current().subject == Identity.system().subject
    end

    test "can set and clear current identity" do
      identity = Identity.new("user-2", "Bob", "bob")
      IdentityProvider.set_current_identity(identity)

      assert IdentityProvider.get_current().subject == "user-2"

      :ok = IdentityProvider.clear_current_identity()

      assert IdentityProvider.get_current().subject == Identity.system().subject
    end
  end
end
