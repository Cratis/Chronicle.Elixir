```elixir
defmodule MyApp.Events.BookAdded do
  use Cratis.Chronicle.Events.EventType, id: "book-added"

  defstruct [:title, :isbn]
end
```
