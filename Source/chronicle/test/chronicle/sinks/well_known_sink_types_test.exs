# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Sinks.WellKnownSinkTypesTest do
  use ExUnit.Case, async: true

  alias Chronicle.Sinks.WellKnownSinkTypes

  describe "WellKnownSinkTypes" do
    test "well-known types resolve to their string identifiers" do
      assert WellKnownSinkTypes.mongodb() == "MongoDB"
      assert WellKnownSinkTypes.sql() == "SQL"
      assert WellKnownSinkTypes.in_memory() == "InMemory"
      assert WellKnownSinkTypes.none() == "None"
    end

    test "resolve/1 maps atoms to string identifiers" do
      assert WellKnownSinkTypes.resolve(:mongodb) == "MongoDB"
      assert WellKnownSinkTypes.resolve(:sql) == "SQL"
      assert WellKnownSinkTypes.resolve(:in_memory) == "InMemory"
      assert WellKnownSinkTypes.resolve(:none) == "None"
    end

    test "resolve/1 passes through raw string identifiers" do
      assert WellKnownSinkTypes.resolve("MongoDB") == "MongoDB"
    end

    test "resolve/1 raises for unknown sink types" do
      assert_raise ArgumentError, fn -> WellKnownSinkTypes.resolve(:unknown) end
    end
  end
end
