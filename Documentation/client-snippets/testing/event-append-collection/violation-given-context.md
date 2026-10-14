```elixir
defmodule MyApp.TestingCollectionViolationContextTest do
  # Shared setup: the reactor is registered, so a duplicate unique value on its
  # follow-up append is rejected by the constraint instead of throwing — the
  # violation shows up on the captured event's result (see the spec).
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingCollectionUniqueValueRecorded,
      MyApp.Events.TestingCollectionUniqueValueFollowUp
    ],
    reactors: [MyApp.Reactors.TestingCollectionUniqueValueReactor]
end
```
