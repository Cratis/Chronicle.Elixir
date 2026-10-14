```elixir
defmodule MyApp.TestingCollectionShipmentContextTest do
  # The shared per-test-module setup: the client starts with the reactor
  # registered, so every test in the module gets it running synchronously
  # against the in-memory kernel. `Chronicle.Testing.wait_for_observers/1` is
  # the deterministic replacement for `WaitForCount`/`WaitTillActive` — see the
  # spec in the next tab.
  use Chronicle.Testing.Case,
    event_types: [
      MyApp.Events.TestingCollectionOrderPlaced,
      MyApp.Events.TestingCollectionShipmentScheduled
    ],
    reactors: [MyApp.Reactors.TestingCollectionShipmentReactor]
end
```
