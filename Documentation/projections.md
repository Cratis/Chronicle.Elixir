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

## Ad-hoc querying with `Chronicle.Projections`

`Chronicle.Projections.query/2` sends a Projection Declaration Language (PDL) string straight to
the kernel and returns the projected entries, without registering a permanent projection or
defining a read model module:

```elixir
{:ok, result} =
  Chronicle.Projections.query("""
  projection OrderSummary
    from OrderPlaced
  """)

result.instances      # decoded as plain maps unless :read_model is given
```

Pass `:read_model` to decode each entry as a struct instead. A declaration with syntax or type
errors returns `{:error, {:invalid_declaration, [%{message:, line:, column:}]}}`. See the shared
[Ad-hoc Querying](/chronicle/projections/projection-declaration-language/adhoc-querying/) page for
the full picture — Elixir now joins C# in supporting this.

`Chronicle.Projections.preview/2` runs an already-registered projection's own declaration the same
way, looked up by read model module or projection identifier.

## Waiting for a projection

`Chronicle.Projections.wait_for/3` polls until a projection has handled a given event sequence
number, or returns `{:error, :timeout}`:

```elixir
{:ok, %{sequence_number: sequence}} =
  Chronicle.EventSequences.EventLog.append_with_result(account_id, event)

:ok = Chronicle.Projections.wait_for(MyApp.ReadModels.Account, sequence)
```

## Event context values

`:occurred` maps to the event's occurred time (`$eventContext(Occurred)`). The old `$occurred`
spelling was rejected by the kernel and is now translated.
