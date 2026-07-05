```elixir
defmodule MyApp.Events.ConstantKeyProductPurchased do
  use Chronicle.Events.EventType, id: "constant-key-product-purchased-v1"

  defstruct [:product_id, :amount]
end

defmodule MyApp.Events.ConstantKeyProductReturned do
  use Chronicle.Events.EventType, id: "constant-key-product-returned-v1"

  defstruct [:product_id, :amount]
end

defmodule MyApp.Events.ConstantKeyPageViewed do
  use Chronicle.Events.EventType, id: "constant-key-page-viewed-v1"

  defstruct [:page_url]
end

defmodule MyApp.ReadModels.StoreMetrics do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{
    ConstantKeyProductPurchased,
    ConstantKeyProductReturned,
    ConstantKeyPageViewed
  }

  defstruct total_purchases: 0, total_returns: 0, net_transactions: 0, total_page_views: 0

  from ConstantKeyProductPurchased,
    key: "$value(store)",
    count: :total_purchases,
    add: [net_transactions: 1]

  from ConstantKeyProductReturned,
    key: "$value(store)",
    count: :total_returns,
    subtract: [net_transactions: 1]

  from ConstantKeyPageViewed,
    key: "$value(store)",
    count: :total_page_views
end
```
