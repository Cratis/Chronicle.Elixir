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
`removed_with/2`, `removed_with_join/2`, `clear_with/2`, `from_every/1` and a nested `children/3`
take the options they take on the read model. `key` identifies the child an event applies to and
`parent_key` the parent it belongs to.

A collection that only ever grows from a single event does not need a `do` block:

```elixir
children :entries, from: MyApp.Events.EntryAdded,
  identified_by: :entry_id,
  key: :entry_id,
  set: [entry_id: :entry_id, name: :name]
```

Unlike a root `join/2`, a join inside a `children` block does not require `:on` — it defaults to
the collection's `identified_by`, since a child is always joined by its own identifying property.
An explicit `:on` that disagrees with `identified_by` is accepted but produces a compile-time
warning rather than an error.

`removed_with_join/2` removes a child when a secondary event — from a different event source —
matches it by a property instead of by the collection's own key:

```elixir
removed_with_join MyApp.Events.EntryArchivedElsewhere, key: :archived_entry_id
```

Use `clear: [:field]` in a mapping, or the `clear_with event, [:field]` sugar, to set a scalar
back to no value. The target field must default to `nil`: a field whose default is a concrete
value (such as `""`) is not nullable to the kernel, and clearing it writes the type default back
instead of no value.

A few mistakes are caught at compile time rather than at registration: a `children` collection
without `:identified_by`, a root `join/2` without `:on`, the same target property assigned twice
by one event's mapping, and a `from`/`join` target or `children` name that is not a field of the
read model's struct.

## Event context values

`:occurred` maps to the event's occurred time (`$eventContext(Occurred)`). The old `$occurred`
spelling was rejected by the kernel and is now translated.
