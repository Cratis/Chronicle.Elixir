# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.ProjectionsDictionariesTest do
  use ExUnit.Case, async: true

  alias Chronicle.Testing.{Projections, UnsupportedProjectionOperation}

  defmodule PriceSet do
    use Chronicle.Events.EventType, id: "testing-dictionaries-price-set"
    defstruct [:sku, :price, :label]
  end

  defmodule PriceWithdrawn do
    use Chronicle.Events.EventType, id: "testing-dictionaries-price-withdrawn"
    defstruct [:sku]
  end

  defmodule ItemSold do
    use Chronicle.Events.EventType, id: "testing-dictionaries-item-sold"
    defstruct [:sku, :quantity]
  end

  defmodule Catalog do
    use Chronicle.ReadModels.ReadModel

    defstruct label: nil, first_label: nil, prices: %{}, first_prices: %{}, sold: %{}, sales: %{}

    from(PriceSet,
      set: [label: :label, prices: {:entry, {:event_content, :sku}, :price}],
      set_once: [first_label: :label, first_prices: {:entry, {:event_content, :sku}, :price}]
    )

    from(PriceWithdrawn, remove: [prices: {:event_content, :sku}])

    from(ItemSold,
      add: [sold: {:entry, {:event_content, :sku}, :quantity}],
      count: [sales: {:event_content, :sku}]
    )
  end

  defmodule ByAuthor do
    use Chronicle.ReadModels.ReadModel
    defstruct edits: %{}

    from(PriceSet, increment: [edits: {:caused_by, :subject}])
  end

  defp apply_all(events) do
    Enum.reduce(events, nil, fn event, instance ->
      {:ok, instance} = Projections.apply_event(Catalog, instance, event)
      instance
    end)
  end

  test "set writes the entry keyed by the event content" do
    catalog = apply_all([%PriceSet{sku: "a", price: 1}, %PriceSet{sku: "b", price: 2}])
    assert catalog.prices == %{"a" => 1, "b" => 2}
  end

  test "set_once keeps the first value of a property and of each entry" do
    catalog =
      apply_all([
        %PriceSet{sku: "a", price: 1, label: "first"},
        %PriceSet{sku: "a", price: 5, label: "second"},
        %PriceSet{sku: "b", price: 2, label: "third"}
      ])

    assert catalog.label == "third"
    assert catalog.first_label == "first"
    assert catalog.prices == %{"a" => 5, "b" => 2}
    assert catalog.first_prices == %{"a" => 1, "b" => 2}
  end

  test "remove deletes only the entry keyed by the event content" do
    catalog =
      apply_all([
        %PriceSet{sku: "a", price: 1},
        %PriceSet{sku: "b", price: 2},
        %PriceWithdrawn{sku: "a"}
      ])

    assert catalog.prices == %{"b" => 2}
  end

  test "add and count accumulate per entry" do
    catalog =
      apply_all([
        %ItemSold{sku: "a", quantity: 2},
        %ItemSold{sku: "a", quantity: 3},
        %ItemSold{sku: "b", quantity: 1}
      ])

    assert catalog.sold == %{"a" => 5, "b" => 1}
    assert catalog.sales == %{"a" => 2, "b" => 1}
  end

  test "an event without a key value leaves the dictionary alone" do
    catalog = apply_all([%PriceSet{sku: "a", price: 1}, %PriceSet{sku: nil, price: 9}])
    assert catalog.prices == %{"a" => 1}
  end

  test "a key from the event context is not evaluated in memory" do
    assert_raise UnsupportedProjectionOperation, ~r/caused_by/, fn ->
      Projections.apply_event(ByAuthor, nil, %PriceSet{sku: "a", price: 1})
    end
  end
end
