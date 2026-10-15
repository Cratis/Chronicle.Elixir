```elixir
defmodule MyApp.Events.ProductPriceProductDefined do
  use Chronicle.Events.EventType, id: "product-price-product-defined"

  defstruct [:price]
end

defmodule MyApp.Events.ProductPriceChanged do
  use Chronicle.Events.EventType, id: "product-price-changed"

  defstruct [:old_price, :new_price]
end

defmodule MyApp.Events.ProductPriceProductsOrdered do
  use Chronicle.Events.EventType, id: "product-price-products-ordered"

  # Each item is a map with :product_id, :displayed_price and :quantity.
  defstruct [:items]
end

# The decision model for one product: its current price, the one before and when it changed.
# A reduced variant: a price older than the previous one is never accepted, even inside the grace period.
defmodule MyApp.ReadModels.ProductPriceDecision do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, current: nil, previous: nil, changed_at: nil

  from MyApp.Events.ProductPriceProductDefined, set: [id: :event_source_id, current: :price]

  from MyApp.Events.ProductPriceChanged,
    set: [current: :new_price, previous: :old_price, changed_at: :occurred]
end

defmodule MyApp.ProductPriceOrderProducts do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.DecisionReads
  alias MyApp.Events.ProductPriceProductsOrdered
  alias MyApp.ReadModels.ProductPriceDecision

  @grace_period_seconds 10 * 60

  def handle(order_id, items, now) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        # One decision read per product in the cart. The set is dynamic: it is whatever the order contains.
        with :ok <- check_prices(items, now) do
          # One event on the order's own event source. The product keys are only read, never appended to,
          # and a price change after the reads rejects the commit.
          EventLog.append(order_id, %ProductPriceProductsOrdered{items: items})
        end
      end)

    result == {:ok, :ok}
  end

  defp check_prices(items, now) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      {:ok, read} = DecisionReads.get(ProductPriceDecision, item.product_id)

      if acceptable?(read.instance, item, now),
        do: {:cont, :ok},
        else: {:halt, {:error, :price_not_accepted}}
    end)
  end

  defp acceptable?(nil, _item, _now), do: false

  defp acceptable?(%ProductPriceDecision{} = price, item, now) do
    price.current == item.displayed_price or
      (price.previous == item.displayed_price and recent?(price.changed_at, now))
  end

  defp recent?(%DateTime{} = changed_at, now),
    do: DateTime.diff(now, changed_at, :second) <= @grace_period_seconds

  defp recent?(changed_at, now) when is_binary(changed_at) do
    case DateTime.from_iso8601(changed_at) do
      {:ok, parsed, _offset} -> recent?(parsed, now)
      _ -> false
    end
  end

  defp recent?(_changed_at, _now), do: false
end
```
