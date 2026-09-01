# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ConceptTest do
  use ExUnit.Case, async: true

  defmodule PersonName do
    use Chronicle.Concept, type: :string
    pii("Legal name of the data subject")
  end

  defmodule Age do
    use Chronicle.Concept, type: :integer
  end

  defmodule Price do
    use Chronicle.Concept, type: :float
  end

  defmodule IsVerified do
    use Chronicle.Concept, type: :boolean
  end

  defmodule ExternalId do
    use Chronicle.Concept, type: :uuid
  end

  defmodule SurrogateEmployeeId do
    use Chronicle.Concept, type: :uuid, event_source_id: true
  end

  describe "use Chronicle.Concept" do
    test "exposes the declared type" do
      assert PersonName.__chronicle_concept__(:type) == :string
    end

    test "defaults value: to the empty string for :string" do
      assert %PersonName{} == %PersonName{value: ""}
    end

    test "defaults value: to zero for :integer" do
      assert %Age{} == %Age{value: 0}
    end

    test "defaults value: to zero for :float" do
      assert %Price{} == %Price{value: 0.0}
    end

    test "defaults value: to false for :boolean" do
      assert %IsVerified{} == %IsVerified{value: false}
    end

    test "defaults value: to the empty string for :uuid" do
      assert %ExternalId{} == %ExternalId{value: ""}
    end

    test "defaults event_source_id? to false" do
      refute PersonName.__chronicle_concept__(:event_source_id?)
    end

    test "exposes event_source_id? when declared" do
      assert SurrogateEmployeeId.__chronicle_concept__(:event_source_id?)
    end
  end

  describe "pii/0,1" do
    test "records details on the module's __chronicle_pii__/0" do
      assert PersonName.__chronicle_pii__() == [{:value, "Legal name of the data subject"}]
    end

    test "defaults details to an empty string" do
      assert Chronicle.ConceptTest.PersonNameWithoutDetails.__chronicle_pii__() == [{:value, ""}]
    end

    test "is empty for a concept that never declares pii" do
      assert Age.__chronicle_pii__() == []
    end
  end

  defmodule PersonNameWithoutDetails do
    use Chronicle.Concept, type: :string
    pii()
  end

  describe "Jason.Encoder" do
    test "encodes a string concept as its wrapped value" do
      assert Jason.encode!(%PersonName{value: "Ada Lovelace"}) == "\"Ada Lovelace\""
    end

    test "encodes an integer concept as its wrapped value" do
      assert Jason.encode!(%Age{value: 42}) == "42"
    end

    test "encodes a boolean concept as its wrapped value" do
      assert Jason.encode!(%IsVerified{value: true}) == "true"
    end

    test "round-trips through Jason as the plain wrapped value" do
      encoded = Jason.encode!(%PersonName{value: "Grace Hopper"})
      assert Jason.decode!(encoded) == "Grace Hopper"
    end

    test "encodes a concept nested inside a plain map as the wrapped value" do
      encoded = Jason.encode!(%{name: %PersonName{value: "Ada"}, age: %Age{value: 30}})
      assert Jason.decode!(encoded) == %{"name" => "Ada", "age" => 30}
    end
  end

  describe "compile-time validation" do
    test "rejects an unknown type" do
      assert_raise ArgumentError, ~r/unknown Chronicle\.Concept type/, fn ->
        Code.compile_string("""
        defmodule Chronicle.ConceptTest.UnknownTypeConcept do
          use Chronicle.Concept, type: :money
        end
        """)
      end
    end

    test "requires a :type option" do
      assert_raise ArgumentError, ~r/requires a :type option/, fn ->
        Code.compile_string("""
        defmodule Chronicle.ConceptTest.MissingTypeConcept do
          use Chronicle.Concept
        end
        """)
      end
    end

    test "rejects pii/0,1 on a concept declared with event_source_id: true" do
      assert_raise ArgumentError, ~r/PII is not supported on a Chronicle\.Concept/, fn ->
        Code.compile_string("""
        defmodule Chronicle.ConceptTest.PiiEventSourceIdConcept do
          use Chronicle.Concept, type: :uuid, event_source_id: true
          pii("should not be allowed")
        end
        """)
      end
    end

    test "allows event_source_id: true when pii is never declared" do
      Code.compile_string("""
      defmodule Chronicle.ConceptTest.PlainSurrogateId do
        use Chronicle.Concept, type: :uuid, event_source_id: true
      end
      """)

      assert Chronicle.ConceptTest.PlainSurrogateId.__chronicle_concept__(:event_source_id?)
    end
  end
end
