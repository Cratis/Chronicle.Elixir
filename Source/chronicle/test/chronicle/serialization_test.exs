# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.SerializationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Schemas.JsonSchemaGenerator
  alias Chronicle.Serialization

  defmodule Title do
    use Chronicle.Concept, type: :string
  end

  defmodule Entry do
    defstruct entry_name: "", item_count: 0
  end

  defmodule Address do
    defstruct street_name: "", house_number: 0
  end

  defmodule Recorded do
    use Chronicle.Events.EventType,
      id: "serialization-recorded",
      types: [entries: {:list, Entry}, address: Address, labels: :map]

    defstruct title: %Title{},
              series_name: "",
              parameters: %{},
              labels: %{},
              entries: [],
              address: nil,
              recorded_at: ~U[2000-01-01 00:00:00Z],
              quantity: 0
  end

  defp sample do
    %Recorded{
      title: %Title{value: "Dune"},
      series_name: "Arrakis",
      parameters: %{"snake_case_key" => 1, "other" => %{"deep_key" => 2}},
      labels: %{"a_b" => "c"},
      entries: [%Entry{entry_name: "first", item_count: 3}],
      address: %Address{street_name: "Main", house_number: 7},
      recorded_at: ~U[2024-05-06 07:08:09Z],
      quantity: 160
    }
  end

  test "encodes struct fields as camelCase at every depth and preserves map keys" do
    encoded = sample() |> Serialization.to_json() |> Jason.decode!()

    assert encoded["seriesName"] == "Arrakis"
    assert encoded["title"] == "Dune"
    assert encoded["parameters"] == %{"snake_case_key" => 1, "other" => %{"deep_key" => 2}}
    assert encoded["entries"] == [%{"entryName" => "first", "itemCount" => 3}]
    assert encoded["address"] == %{"streetName" => "Main", "houseNumber" => 7}
    assert encoded["recordedAt"] == "2024-05-06T07:08:09Z"
  end

  test "round-trips an event through the wire format" do
    original = sample()
    json = Serialization.to_json(original)

    assert Serialization.decode(Recorded, json) == original
  end

  test "an integer default accepts a whole-number float from the kernel" do
    decoded = Serialization.decode(Recorded, %{"quantity" => 160.0})
    assert decoded.quantity == 160
    assert Serialization.decode(Recorded, %{"quantity" => 1.5}).quantity == 1.5
  end

  test "decoding ignores unknown keys and tolerates PascalCase keys" do
    decoded = Serialization.decode(Recorded, %{"SeriesName" => "X", "nope" => 1})
    assert decoded.series_name == "X"
  end

  test "schema agrees with the payload at every depth" do
    schema = Recorded |> JsonSchemaGenerator.generate(key_transform: :camel) |> Jason.decode!()
    props = schema["properties"]

    assert props["parameters"]["type"] == "object"
    assert props["labels"]["type"] == "object"
    assert props["seriesName"]["type"] == "string"

    assert props["entries"]["items"]["properties"] |> Map.keys() |> Enum.sort() == [
             "entryName",
             "itemCount"
           ]

    assert props["address"]["properties"] |> Map.keys() |> Enum.sort() == [
             "houseNumber",
             "streetName"
           ]

    payload = sample() |> Serialization.to_json() |> Jason.decode!()
    assert_keys_covered(payload, schema)
  end

  test "map default with entries infers additionalProperties" do
    defmodule WithMap do
      defstruct counts: %{"a" => 1}
    end

    schema = WithMap |> JsonSchemaGenerator.generate() |> Jason.decode!()

    assert schema["properties"]["counts"] == %{
             "type" => "object",
             "additionalProperties" => %{"type" => "number"}
           }
  end

  # every key of a struct-backed object in the payload must exist in the schema
  defp assert_keys_covered(payload, %{"properties" => props}) when props != %{} do
    for {key, value} <- payload do
      assert Map.has_key?(props, key), "payload key #{key} missing from schema"
      assert_keys_covered(value, props[key])
    end
  end

  defp assert_keys_covered(list, %{"items" => items}) when is_list(list),
    do: Enum.each(list, &assert_keys_covered(&1, items))

  defp assert_keys_covered(_payload, _schema), do: :ok
end
