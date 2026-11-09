# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.DictionaryEntriesTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator

  defmodule PriceSet do
    use Chronicle.Events.EventType, id: "dictionary-entries-price-set"
    defstruct [:product_sku, :price]
  end

  defmodule PriceWithdrawn do
    use Chronicle.Events.EventType, id: "dictionary-entries-price-withdrawn"
    defstruct [:product_sku]
  end

  defmodule ItemSold do
    use Chronicle.Events.EventType, id: "dictionary-entries-item-sold"
    defstruct [:product_sku, :quantity]
  end

  defmodule Catalog do
    use Chronicle.ReadModels.ReadModel

    defstruct prices: %{}, first_prices: %{}, sold: %{}, sales: %{}, editors: %{}, nested: %{}

    from(PriceSet,
      set: [prices: {:entry, {:event_content, :product_sku}, :price}],
      set_once: [first_prices: {:entry, {:event_content, :product_sku}, :price}],
      increment: [editors: {:caused_by, :user_name}]
    )

    from(PriceWithdrawn,
      remove: [prices: {:event_content, :product_sku}],
      decrement: [editors: {:caused_by, :subject}]
    )

    from(ItemSold,
      add: [sold: {:entry, {:event_content, :product_sku}, :quantity}],
      count: [sales: {:event_content, :product_sku}],
      subtract: [nested: {:entry, {:event_content, "product.sku"}, :quantity}]
    )
  end

  defp properties(event) do
    Catalog
    |> Coordinator.build_projection_definition()
    |> Map.get(:From)
    |> Enum.find(&(Map.get(Map.get(&1, :Key), :Id) == event.__chronicle_event_type__(:id)))
    |> Map.get(:Value)
    |> Map.get(:Properties)
  end

  test "set targets the dictionary entry keyed by the camelCase event content property" do
    assert properties(PriceSet)["prices.$eventContent.productSku"] == "price"
  end

  test "set_once wraps the value in $setOnce" do
    assert properties(PriceSet)["first_prices.$eventContent.productSku"] == "$setOnce(price)"
  end

  test "remove removes the dictionary entry keyed by the event content" do
    assert properties(PriceWithdrawn)["prices.$eventContent.productSku"] == "$remove"
  end

  test "add, subtract and count target dictionary entries" do
    properties = properties(ItemSold)

    assert properties["sold.$eventContent.productSku"] == "$add(quantity)"
    assert properties["sales.$eventContent.productSku"] == "$count"
    assert properties["nested.$eventContent.product.sku"] == "$subtract(quantity)"
  end

  test "a caused-by key names the identity property" do
    assert properties(PriceSet)["editors.$causedBy.userName"] == "$increment"
    assert properties(PriceWithdrawn)["editors.$causedBy.subject"] == "$decrement"
  end

  test "a dictionary entry does not also map the whole dictionary" do
    refute Map.has_key?(properties(PriceSet), "prices")
    refute Map.has_key?(properties(PriceWithdrawn), "prices")
  end

  test "set_once on a plain property" do
    assert Coordinator.build_properties(set_once: [registered_at: :occurred]) == %{
             "registered_at" => "$setOnce($eventContext(Occurred))"
           }
  end

  test "caused_by expressions resolve to $causedBy" do
    assert Coordinator.build_properties(
             set: [
               author_id: {:caused_by, :subject},
               author_name: {:caused_by, :name},
               author_user: {:caused_by, :user_name}
             ]
           ) == %{
             "author_id" => "$causedBy(subject)",
             "author_name" => "$causedBy(name)",
             "author_user" => "$causedBy(userName)"
           }
  end

  test "a bare caused_by is an event field, not the identity" do
    assert Coordinator.build_properties(set: [author: :caused_by]) == %{"author" => "causedBy"}
  end

  test "an unknown caused_by property is rejected" do
    assert_raise ArgumentError, ~r/:subject, :name or :user_name/, fn ->
      Coordinator.build_properties(set: [author: {:caused_by, :email}])
    end
  end

  test "remove without a key source is rejected" do
    assert_raise ArgumentError, ~r/needs the key of the entry to remove/, fn ->
      Coordinator.build_properties(remove: [prices: :product_sku])
    end
  end

  test "event context dictionary keys keep their existing form" do
    assert Coordinator.build_properties(increment: [counts: {:event_context, :type}]) == %{
             "counts.$eventContext.type" => "$increment"
           }
  end

  test "the same property twice in one mapping is a compile-time error" do
    assert_raise CompileError, ~r/Property 'prices\[.*\]' has already been defined/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Registration.DictionaryEntriesTest.Duplicate do
        use Chronicle.ReadModels.ReadModel
        defstruct prices: %{}

        from(Chronicle.Registration.DictionaryEntriesTest.PriceSet,
          set: [prices: {:entry, {:event_content, :product_sku}, :price}],
          remove: [prices: {:event_content, :product_sku}]
        )
      end
      """)
    end
  end

  test "entries keyed differently in one mapping are separate targets" do
    {{:module, module, _, _}, _} =
      Code.eval_string("""
      defmodule Chronicle.Registration.DictionaryEntriesTest.DifferentKeys do
        use Chronicle.ReadModels.ReadModel
        defstruct counts: %{}

        from(Chronicle.Registration.DictionaryEntriesTest.PriceSet,
          increment: [counts: {:event_content, :product_sku}],
          set: [counts: {:entry, {:caused_by, :subject}, :price}]
        )
      end
      """)

    assert module.__chronicle_read_model__(:has_projection?)
  end

  test "a dictionary entry on a missing property is a compile-time error" do
    assert_raise CompileError, ~r/missing/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Registration.DictionaryEntriesTest.MissingField do
        use Chronicle.ReadModels.ReadModel
        defstruct prices: %{}

        from(Chronicle.Registration.DictionaryEntriesTest.PriceWithdrawn,
          remove: [missing: {:event_content, :product_sku}]
        )
      end
      """)
    end
  end
end
