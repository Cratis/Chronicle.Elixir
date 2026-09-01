```elixir
defmodule MyApp.Projections.DecSetPropsAccountProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecSetPropsAccount

  alias MyApp.Events.{DecSetPropsAccountOpened, DecSetPropsMoneyDeposited}

  from DecSetPropsAccountOpened,
    set: [
      account_number: :number,
      # `owner` is a nested object on the event — the dot-path expression
      # reaches into it the same way Chronicle's kernel resolves any other
      # nested event property.
      customer_name: "owner.name",
      balance: "$value(42.0)",
      is_active: "$value(true)",
      opened_at: :timestamp
    ]

  from DecSetPropsMoneyDeposited,
    set: [
      balance: :amount,
      last_transaction: :timestamp
    ]
end
```
