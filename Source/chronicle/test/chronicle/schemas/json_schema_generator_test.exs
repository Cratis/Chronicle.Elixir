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

  defmodule PersonNameConcept do
    use Chronicle.Concept, type: :string
    pii("Legal name of the data subject")
  end

  defmodule AgeConcept do
    use Chronicle.Concept, type: :integer
  end

  defmodule AddressValueObject do
    defstruct street: %PersonNameConcept{}, postal_code: ""
  end

  defmodule EmployeeRegisteredWithConcept do
    use Chronicle.Events.EventType, id: "employee-registered-with-concept"

    defstruct name: %PersonNameConcept{},
              age: %AgeConcept{},
              department: "",
              home_address: %AddressValueObject{},
              aliases: [%PersonNameConcept{}]
  end

  defmodule EmployeeWithConcept do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", name: %PersonNameConcept{}, department: ""
  end

  defmodule RedundantlyAnnotatedEvent do
    use Chronicle.Events.EventType, id: "redundantly-annotated-event"
    defstruct name: %PersonNameConcept{}

    pii(:name, "declared again at the property level")
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
                 "metadataType" => "PII",
                 "details" => "Customer email address"
               }
             ]

      assert schema["properties"]["fullName"]["compliance"] == [
               %{"metadataType" => "PII", "details" => ""}
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
                 "metadataType" => "PII",
                 "details" => "Personal email"
               }
             ]
    end

    test "resolves PII from a concept type on an event schema" do
      schema =
        EmployeeRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      assert schema["properties"]["name"] == %{
               "type" => "string",
               "compliance" => [
                 %{"metadataType" => "PII", "details" => "Legal name of the data subject"}
               ]
             }
    end

    test "resolves PII from a concept type on a read model schema" do
      schema =
        EmployeeWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :identity)
        |> Jason.decode!()

      assert schema["properties"]["name"] == %{
               "type" => "string",
               "compliance" => [
                 %{"metadataType" => "PII", "details" => "Legal name of the data subject"}
               ]
             }
    end

    test "leaves a concept field without pii/0,1 free of compliance metadata" do
      schema =
        EmployeeRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["age"], "compliance")
      assert schema["properties"]["age"] == %{"type" => "number"}
    end

    test "describes a concept field as its wrapped value, not the wrapper struct" do
      schema =
        EmployeeRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["name"], "properties")
      assert schema["properties"]["name"]["type"] == "string"
    end

    test "descends into a plain nested struct to find PII on a leaf" do
      schema =
        EmployeeRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      address_schema = schema["properties"]["homeAddress"]
      assert address_schema["type"] == "object"
      refute Map.has_key?(address_schema, "compliance")

      assert address_schema["properties"]["street"]["compliance"] == [
               %{"metadataType" => "PII", "details" => "Legal name of the data subject"}
             ]

      refute Map.has_key?(address_schema["properties"]["postalCode"], "compliance")
    end

    test "carries compliance metadata on the items schema for a list of PII concepts" do
      schema =
        EmployeeRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      aliases_schema = schema["properties"]["aliases"]
      assert aliases_schema["type"] == "array"
      refute Map.has_key?(aliases_schema, "compliance")

      assert aliases_schema["items"]["compliance"] == [
               %{"metadataType" => "PII", "details" => "Legal name of the data subject"}
             ]
    end

    test "de-duplicates compliance metadata reached through more than one path" do
      schema =
        RedundantlyAnnotatedEvent
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      assert schema["properties"]["name"]["compliance"] == [
               %{"metadataType" => "PII", "details" => "Legal name of the data subject"}
             ]
    end
  end
end
