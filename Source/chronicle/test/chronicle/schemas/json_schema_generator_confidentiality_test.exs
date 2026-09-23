# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Schemas.JsonSchemaGeneratorConfidentialityTest do
  use ExUnit.Case, async: true

  alias Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported
  alias Chronicle.Schemas.JsonSchemaGenerator

  defmodule EncryptedEvent do
    use Chronicle.Events.EventType, id: "encrypted-event"
    defstruct [:partner_name, :api_key, :webhook_secret]

    encrypted(:api_key, :subject, "Partner API key")
    encrypted(:webhook_secret, :namespace)
  end

  defmodule EncryptedReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", license_token: "", partner_name: ""
    encrypted(:license_token, :global)
  end

  defmodule ApiKeyConcept do
    use Chronicle.Concept, type: :string
    encrypted(:subject, "Partner API key")
  end

  defmodule WebhookSecretConcept do
    use Chronicle.Concept, type: :string
    encrypted(:namespace)
  end

  defmodule ContactDetailsValueObject do
    defstruct phone: %ApiKeyConcept{}, fax: ""
  end

  defmodule VendorRegisteredWithConcept do
    use Chronicle.Events.EventType, id: "vendor-registered-with-concept"

    defstruct api_key: %ApiKeyConcept{},
              webhook_secret: %WebhookSecretConcept{},
              vendor_name: "",
              contact: %ContactDetailsValueObject{},
              tokens: [%ApiKeyConcept{}]
  end

  defmodule RedundantlyAnnotatedEncryptedEvent do
    use Chronicle.Events.EventType, id: "redundantly-annotated-encrypted-event"
    defstruct api_key: %ApiKeyConcept{}

    encrypted(:api_key, :subject, "declared again at the property level")
  end

  defmodule ConflictedEvent do
    use Chronicle.Events.EventType, id: "conflicted-event"
    defstruct [:value]

    pii(:value)
    encrypted(:value)
  end

  defmodule EncryptedOnlyConcept do
    use Chronicle.Concept, type: :string
    encrypted()
  end

  defmodule EventWithCrossSourceConflict do
    use Chronicle.Events.EventType, id: "event-with-cross-source-conflict"
    defstruct value: %EncryptedOnlyConcept{}

    # Neither this module's own pii/1,2 nor EncryptedOnlyConcept's own
    # encrypted/0,1 conflicts with itself - the conflict only exists in the
    # union once the concept's type-level encrypted metadata and this
    # property's own pii metadata land on the same leaf.
    pii(:value)
  end

  describe "generate/2 - security metadata" do
    test "embeds EncryptedSubject security metadata on the default-scoped property" do
      schema =
        EncryptedEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      assert schema["properties"]["apiKey"]["security"] == [
               %{"metadataType" => "EncryptedSubject", "details" => "Partner API key"}
             ]
    end

    test "embeds EncryptedNamespace security metadata on a namespace-scoped property" do
      schema =
        EncryptedEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      assert schema["properties"]["webhookSecret"]["security"] == [
               %{"metadataType" => "EncryptedNamespace", "details" => ""}
             ]
    end

    test "embeds EncryptedGlobal security metadata on a global-scoped read model property" do
      schema =
        EncryptedReadModel
        |> JsonSchemaGenerator.generate(key_transform: :identity)
        |> Jason.decode!()

      assert schema["properties"]["license_token"]["security"] == [
               %{"metadataType" => "EncryptedGlobal", "details" => ""}
             ]
    end

    test "leaves non-encrypted properties without security metadata" do
      schema =
        EncryptedEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["partnerName"], "security")
    end

    test "leaves an encrypted property without compliance metadata" do
      schema =
        EncryptedEvent |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["apiKey"], "compliance")
    end

    test "resolves security metadata from a concept type on an event schema" do
      schema =
        VendorRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      assert schema["properties"]["apiKey"] == %{
               "type" => "string",
               "security" => [
                 %{"metadataType" => "EncryptedSubject", "details" => "Partner API key"}
               ]
             }

      assert schema["properties"]["webhookSecret"] == %{
               "type" => "string",
               "security" => [%{"metadataType" => "EncryptedNamespace", "details" => ""}]
             }
    end

    test "leaves a concept field without encrypted/0,1 free of security metadata" do
      schema =
        VendorRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      refute Map.has_key?(schema["properties"]["vendorName"], "security")
      assert schema["properties"]["vendorName"] == %{"type" => "string"}
    end

    test "descends into a plain nested struct to find Encrypted on a leaf" do
      schema =
        VendorRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      contact_schema = schema["properties"]["contact"]
      assert contact_schema["type"] == "object"
      refute Map.has_key?(contact_schema, "security")

      assert contact_schema["properties"]["phone"]["security"] == [
               %{"metadataType" => "EncryptedSubject", "details" => "Partner API key"}
             ]

      refute Map.has_key?(contact_schema["properties"]["fax"], "security")
    end

    test "carries security metadata on the items schema for a list of Encrypted concepts" do
      schema =
        VendorRegisteredWithConcept
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      tokens_schema = schema["properties"]["tokens"]
      assert tokens_schema["type"] == "array"
      refute Map.has_key?(tokens_schema, "security")

      assert tokens_schema["items"]["security"] == [
               %{"metadataType" => "EncryptedSubject", "details" => "Partner API key"}
             ]
    end

    test "de-duplicates security metadata reached through more than one path" do
      schema =
        RedundantlyAnnotatedEncryptedEvent
        |> JsonSchemaGenerator.generate(key_transform: :camel)
        |> Jason.decode!()

      assert schema["properties"]["apiKey"]["security"] == [
               %{"metadataType" => "EncryptedSubject", "details" => "Partner API key"}
             ]
    end

    test "raises PiiAndEncryptedCombinedNotSupported for a property carrying both pii and encrypted" do
      assert_raise PiiAndEncryptedCombinedNotSupported, fn ->
        JsonSchemaGenerator.generate(ConflictedEvent, key_transform: :camel)
      end
    end

    test "raises PiiAndEncryptedCombinedNotSupported for a property-level pii combined with a type-level encrypted" do
      assert_raise PiiAndEncryptedCombinedNotSupported, fn ->
        JsonSchemaGenerator.generate(EventWithCrossSourceConflict, key_transform: :camel)
      end
    end
  end
end
