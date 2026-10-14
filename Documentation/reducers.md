---
sharedTopicBridge: true
---

# Reducers

Reducers are shared Chronicle read-model behavior. Use the shared reducer docs for the model, lifecycle, filtering, and client-tabbed examples.

- [Reducers](/chronicle/reducers/)
- [Getting started with reducers](/chronicle/reducers/getting-started/)
- [Reducer event processing](/chronicle/reducers/event-processing/)
- [Elixir client setup](./get-started.md)


## Passive reducers

`use Chronicle.Reducers.Reducer` accepts an `:active` option, defaulting to `true`. Set it
to `false` for a **passive** reducer: its read model is only computed on demand (e.g. via
`Chronicle.ReadModels.get_instance_by_id/3`) instead of being kept warm in the background as
events are appended — useful for a reducer whose read model backs a command-side decision
that's read rarely, where continuous observation would be wasted work. Mirrors C#'s
`ReducerAttribute.IsActive`.

```elixir
defmodule MyApp.Reducers.AccountReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.AccountInfo, active: false

  alias MyApp.Events.OrderPlaced

  @handles OrderPlaced

  @impl true
  def reduce(%OrderPlaced{}, model, _context), do: model
end
```

## Pinning the id

`use Chronicle.Reducers.Reducer` defaults the reducer's id to its full module name. Renaming
or moving the module then changes that id, and Chronicle treats it as a *different* reducer —
its read model observation position resets. Pin the id explicitly so the module can be renamed
or moved freely:

```elixir
use Chronicle.Reducers.Reducer, id: "account-reducer", model: MyApp.ReadModels.AccountInfo
```

A reducer relying on the module-name default gets a one-time warning (per module, for the life
of the BEAM node) from [discovery](./discovery.md), naming the module and showing this fix. See
[Discovery and artifact identity drift](./discovery.md).

## Replay lifecycle hooks

Reducers support the same optional `on_replay_begin/0`, `on_replay_end/0`,
`on_partition_replay_begin/1`, and `on_partition_replay_end/1` callbacks as reactors — see
[Replay lifecycle hooks](./reactors.md#replay-lifecycle-hooks) for details. They run outside
normal `reduce/3` dispatch and are not events to reduce.

## Pinned generation delivery

By default (`:compatibility`), Chronicle upgrades every event to the handled module's own
generation before delivery, so `reduce/3` always sees that generation's shape regardless of which
generation was actually appended. That is the right default when the reducer is written against
the current generation.

Set `generation_delivery: :pinned` when the reducer is written against an **older** generation and
must see events exactly as that generation was appended, instead of upgraded to the current one:

```elixir
use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.AccountInfo, generation_delivery: :pinned
```

`context.appended_generation` then tells you which generation was actually appended (`0` means
unknown — an older kernel, or an event appended outside a registered event source).

A client-wide default applies to every reducer that doesn't set its own `:generation_delivery`:

```elixir
{Chronicle.Client,
  ...
  event_generation_delivery: :pinned}
```

A reducer's own option always wins over the client default. With `:pinned`, a reducer handling two
generations of the same event type id has no single generation to pin to and raises
`Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver` on start.
