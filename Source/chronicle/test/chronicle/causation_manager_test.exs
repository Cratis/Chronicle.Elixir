# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.CausationManagerTest do
  use ExUnit.Case, async: true

  alias Chronicle.{CausationManager, CausationType}

  describe "CausationManager" do
    setup do
      CausationManager.clear()
      :ok
    end

    test "provides default root when unset" do
      [root] = CausationManager.get_current_chain()
      assert root.type.value == CausationType.root().value
    end

    test "can define root and append entries" do
      root = CausationManager.define_root(%{application: "sample"})
      added = CausationManager.add("MyApp.Command.CreateAccount", %{account_id: "account-1"})
      chain = CausationManager.get_current_chain()

      assert Enum.at(chain, 0).type.value == root.type.value
      assert Enum.at(chain, 1).type.value == added.type.value
      assert Enum.at(chain, 1).properties["account_id"] == "account-1"
    end

    test "clear removes current chain state" do
      CausationManager.define_root(%{application: "sample"})
      CausationManager.add("MyApp.Command.Deposit", %{})
      :ok = CausationManager.clear()

      [root] = CausationManager.get_current_chain()
      assert root.type.value == CausationType.root().value
      assert root.properties == %{}
    end
  end
end
