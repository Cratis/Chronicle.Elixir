```elixir
defmodule MyApp.Events.ChoosingStyleBookRegistered do
  use Chronicle.Events.EventType, id: "choosing-style-book-registered"

  defstruct [:title, :isbn]
end

defmodule MyApp.Events.ChoosingStyleBookBorrowed do
  use Chronicle.Events.EventType, id: "choosing-style-book-borrowed"

  defstruct [:member_name]
end

defmodule MyApp.Events.ChoosingStyleBookReturned do
  use Chronicle.Events.EventType, id: "choosing-style-book-returned"

  defstruct []
end
```
