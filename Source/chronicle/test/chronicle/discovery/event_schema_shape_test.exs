# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.EventSchemaShapeTest do
  use ExUnit.Case, async: true

  alias Chronicle.Discovery.EventSchemaShape

  describe "of/1" do
    test "normalizes a flat object schema" do
      schema =
        ~s({"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}})

      assert EventSchemaShape.of(schema) ==
               %{
                 "type" => "object",
                 "properties" => %{
                   "name" => %{"type" => "string"},
                   "age" => %{"type" => "number"}
                 }
               }
    end

    test "is insensitive to property declaration order" do
      a = ~s({"type":"object","properties":{"a":{"type":"string"},"b":{"type":"string"}}})
      b = ~s({"type":"object","properties":{"b":{"type":"string"},"a":{"type":"string"}}})

      assert EventSchemaShape.of(a) == EventSchemaShape.of(b)
    end

    test "treats integer and number as the same category" do
      integer_schema = ~s({"type":"object","properties":{"count":{"type":"integer"}}})
      number_schema = ~s({"type":"object","properties":{"count":{"type":"number"}}})

      assert EventSchemaShape.of(integer_schema) == EventSchemaShape.of(number_schema)
    end

    test "strips nullability" do
      plain = ~s({"type":"object","properties":{"name":{"type":"string"}}})
      nullable = ~s({"type":"object","properties":{"name":{"type":["string","null"]}}})

      assert EventSchemaShape.of(plain) == EventSchemaShape.of(nullable)
    end

    test "detects an added property as a different shape" do
      before = ~s({"type":"object","properties":{"name":{"type":"string"}}})

      after_adding =
        ~s({"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}})

      refute EventSchemaShape.of(before) == EventSchemaShape.of(after_adding)
    end

    test "detects a retyped property as a different shape" do
      as_string = ~s({"type":"object","properties":{"value":{"type":"string"}}})
      as_boolean = ~s({"type":"object","properties":{"value":{"type":"boolean"}}})

      refute EventSchemaShape.of(as_string) == EventSchemaShape.of(as_boolean)
    end

    test "resolves a $ref against the root schema" do
      schema = ~s({
        "type": "object",
        "properties": {"address": {"$ref": "#/$defs/Address"}},
        "$defs": {"Address": {"type": "object", "properties": {"street": {"type": "string"}}}}
      })

      inline = ~s({
        "type": "object",
        "properties": {"address": {"type": "object", "properties": {"street": {"type": "string"}}}}
      })

      assert EventSchemaShape.of(schema) == EventSchemaShape.of(inline)
    end

    test "returns nil for an unresolved $ref" do
      schema = ~s({"type":"object","properties":{"address":{"$ref":"#/$defs/Missing"}}})

      assert EventSchemaShape.of(schema) == nil
    end

    test "collapses a single non-null anyOf alternative" do
      schema = ~s({
        "type": "object",
        "properties": {"value": {"anyOf": [{"type": "null"}, {"type": "string"}]}}
      })

      plain = ~s({"type":"object","properties":{"value":{"type":"string"}}})

      assert EventSchemaShape.of(schema) == EventSchemaShape.of(plain)
    end

    test "returns nil for a non-object schema" do
      assert EventSchemaShape.of(~s("just a string")) == nil
    end

    test "returns nil for an object schema with no properties" do
      assert EventSchemaShape.of(~s({"type":"object"})) == nil
    end

    test "returns nil for invalid JSON" do
      assert EventSchemaShape.of("not json") == nil
    end
  end
end
