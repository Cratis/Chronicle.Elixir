---
sharedTopicBridge: true
---

# Projections

Projections are shared Chronicle read-model behavior. Use the shared docs for projection styles, model-bound projections, declarative projections, and client-tabbed examples.

- [Projections](/chronicle/projections/)
- [Choosing a read model style](/chronicle/projections/choosing-a-read-model-style/)
- [Model-bound projections](/chronicle/projections/model-bound/)
- [Declarative projections](/chronicle/projections/declarative/)
- [Elixir client setup](./get-started.md)

## Child collections

`children/2,3` declares a list on the parent that grows, changes and shrinks with events. Mirrors
the .NET `[ChildrenFrom<T>]`. It works in `use Chronicle.ReadModels.ReadModel` and
`use Chronicle.Projections.Projection`:

```elixir
defmodule MyApp.ReadModels.Basket do
  use Chronicle.ReadModels.ReadModel, types: [items: {:list, MyApp.ReadModels.BasketItem}]

  defstruct basket_id: "", items: []

  from MyApp.Events.BasketCreated, set: [basket_id: :event_source_id]

  children :items, identified_by: :item_id do
    from MyApp.Events.ItemAdded,
      key: :item_id,
      parent_key: :event_source_id,
      set: [item_id: :item_id, name: :name, quantity: :quantity]

    from MyApp.Events.QuantityIncreased,
      key: :item_id,
      parent_key: :event_source_id,
      add: [quantity: :amount]

    removed_with MyApp.Events.ItemRemoved, key: :item_id, parent_key: :event_source_id
  end
end
```

`identified_by` names the property that identifies a child. Inside the block `from/2`, `join/2`,
`removed_with/2`, `from_every/1` and a nested `children/3` take the options they take on the read
model. `key` identifies the child an event applies to and `parent_key` the parent it belongs to.

Use `clear: [:field]` in a mapping to set a scalar back to no value.

## Event context values

`:occurred` maps to the event's occurred time (`$eventContext(Occurred)`). The old `$occurred`
spelling was rejected by the kernel and is now translated.
