```elixir
defmodule MyApp.Events.GetStartedBookAdded do
  use Chronicle.Events.EventType, id: "get-started-book-added"

  defstruct [:title, :isbn]
end

defmodule MyApp.Events.GetStartedBookBorrowed do
  use Chronicle.Events.EventType, id: "get-started-book-borrowed"

  defstruct [:member_name]
end

defmodule MyApp.Events.GetStartedBookReturned do
  use Chronicle.Events.EventType, id: "get-started-book-returned"

  defstruct []
end
```
