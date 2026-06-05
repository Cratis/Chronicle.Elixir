# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.CorrelationIdTest do
  use ExUnit.Case, async: true

  alias Chronicle.Correlation.{CorrelationId, CorrelationIdManager}

  describe "CorrelationId" do
    test "create/0 returns UUID-like id" do
      %CorrelationId{value: value} = CorrelationId.create()
      assert value =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "not_set/0 returns zero guid" do
      assert CorrelationId.not_set().value == "00000000-0000-0000-0000-000000000000"
    end
  end

  describe "CorrelationIdManager" do
    setup do
      Process.delete({CorrelationIdManager, :current})
      :ok
    end

    test "returns created id when not set" do
      assert %CorrelationId{} = CorrelationIdManager.current()
    end

    test "returns set id" do
      CorrelationIdManager.set_current("correlation-id")
      assert CorrelationIdManager.current().value == "correlation-id"
    end

    test "clear sets a fresh id" do
      CorrelationIdManager.set_current("existing-id")
      cleared = CorrelationIdManager.clear()

      assert %CorrelationId{} = cleared
      assert cleared.value != "existing-id"
      assert CorrelationIdManager.current().value == cleared.value
    end
  end
end
