```elixir
defmodule MyApp.Projections.DecSetPropsCombinedAccountProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecSetPropsAccount

  alias MyApp.Events.{DecSetPropsAccountOpened, DecSetPropsMoneyDeposited}

  # AutoMap fills every property whose name matches the event automatically;
  # only the two exceptions below need an explicit set:.
  from DecSetPropsAccountOpened,
    set: [
      customer_name: "owner.name",
      is_active: "$value(true)"
    ]

  # Uses AutoMap for every property.
  from DecSetPropsMoneyDeposited
end
```
