```elixir
defmodule MyApp.Events.GetStartedBookAdded do
  use Cratis.Chronicle.Events.EventType, id: "get-started-book-added"

  defstruct [:title, :isbn]
end

defmodule MyApp.Events.GetStartedBookBorrowed do
  use Cratis.Chronicle.Events.EventType, id: "get-started-book-borrowed"

  defstruct [:member_name]
end

defmodule MyApp.Events.GetStartedBookReturned do
  use Cratis.Chronicle.Events.EventType, id: "get-started-book-returned"

  defstruct []
end
```
