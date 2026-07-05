```elixir
defmodule MyApp.Events.BookBorrowed do
  use Chronicle.Events.EventType, id: "book-borrowed"

  defstruct [:member_name]
end

defmodule MyApp.Events.BookReturned do
  use Chronicle.Events.EventType, id: "book-returned"

  defstruct []
end
```
