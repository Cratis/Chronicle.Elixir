```elixir
defmodule MyApp.Events.BookAdded do
  use Chronicle.Events.EventType, id: "book-added"

  defstruct [:title, :isbn]
end
```
