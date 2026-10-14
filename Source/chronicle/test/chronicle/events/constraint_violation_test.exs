# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConstraintViolationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.ConstraintViolation

  describe "details/1" do
    test "maps well-known keys to atoms on the wire (:Details) shape" do
      violation = %{
        ConstraintName: "unique-email",
        Details: %{
          "PropertyName" => "Email",
          "PropertyValue" => "jane@example.com"
        }
      }

      assert ConstraintViolation.details(violation) == %{
               property_name: "Email",
               property_value: "jane@example.com"
             }
    end

    test "maps well-known keys to atoms on the resolved (:details) shape" do
      violation = %{
        details: %{
          "ClosedBy" => "period-closed",
          "ClosedAtSequenceNumber" => 42
        }
      }

      assert ConstraintViolation.details(violation) == %{
               closed_by: "period-closed",
               closed_at_sequence_number: 42
             }
    end

    test "keeps an unrecognized key as its original string key" do
      violation = %{details: %{"SomethingElse" => "value"}}

      assert ConstraintViolation.details(violation) == %{"SomethingElse" => "value"}
    end

    test "returns an empty map when there are no details" do
      assert ConstraintViolation.details(%{}) == %{}
      assert ConstraintViolation.details(%{ConstraintName: "x"}) == %{}
      assert ConstraintViolation.details(nil) == %{}
    end
  end
end
