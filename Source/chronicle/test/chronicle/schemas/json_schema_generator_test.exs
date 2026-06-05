# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Schemas.JsonSchemaGeneratorTest do
  use ExUnit.Case, async: true

  alias Chronicle.Schemas.JsonSchemaGenerator

  defmodule PlainEvent do
    use Chronicle.Events.EventType, id: "plain-event"
    defstruct first_name: "", age: 0, active: false
  end

  defmodule PiiEvent do
    use Chronicle.Events.EventType, id: "pii-event"
    defstruct [:customer_id, :email, :full_name]

    pii(:email, "Customer email address")
    pii(:full_name)
  end

  defmodule PiiReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", email: "", total_orders: 0
    pii(:email, "Personal email")
  end

  describe "generate/2" do
    test "produces an object schema with camelCase keys for events" do
      schema =
        PlainEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "firstName")
      assert schema["properties"]["age"] == %{"type" => "number"}
      assert schema["properties"]["active"] == %{"type" => "boolean"}
      assert schema["properties"]["firstName"] == %{"type" => "string"}
    end

    test "keeps snake_case keys for read models" do
      schema =
        PiiReadModel |> JsonSchemaGenerator.generate(key_transform: :identity) |> Jason.decode!()

      assert Map.has_key?(schema["properties"], "total_orders")
    end

    test "embeds PII compliance metadata on adorned event properties" do
      schema = PiiEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      assert schema["properties"]["email"]["compliance"] == [
               %{
                 "metadataType" => "cae5580e-83d6-44dc-9d7a-a72e8a2f17d7",
                 "details" => "Customer email address"
               }
             ]

      assert schema["properties"]["fullName"]["compliance"] == [
               %{"metadataType" => "cae5580e-83d6-44dc-9d7a-a72e8a2f17d7", "details" => ""}
             ]
    end

    test "leaves non-PII properties without compliance metadata" do
      schema = PiiEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["customerId"], "compliance")
    end

    test "embeds PII compliance metadata on adorned read model properties" do
      schema =
        PiiReadModel |> JsonSchemaGenerator.generate(key_transform: :identity) |> Jason.decode!()

      assert schema["properties"]["email"]["compliance"] == [
               %{
                 "metadataType" => "cae5580e-83d6-44dc-9d7a-a72e8a2f17d7",
                 "details" => "Personal email"
               }
             ]
    end
  end
end
