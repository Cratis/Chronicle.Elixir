```elixir
defmodule ReactorSideEffectsSourceEventBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-source-event-book-reserved"

  # Event source ids are plain strings in Elixir — no typed-id wrapper needed.
  defstruct [:member_id, :isbn]
end
```
