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

## Replay lifecycle hooks

Reducers support the same optional `on_replay_begin/0`, `on_replay_end/0`,
`on_partition_replay_begin/1`, and `on_partition_replay_end/1` callbacks as reactors — see
[Replay lifecycle hooks](./reactors.md#replay-lifecycle-hooks) for details. They run outside
normal `reduce/3` dispatch and are not events to reduce.
