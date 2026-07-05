```elixir
defmodule MyApp.Events.ChoosingStyleBookRegistered do
  use Chronicle.Events.EventType

  defstruct [:title, :isbn]
end

defmodule MyApp.Events.ChoosingStyleBookBorrowed do
  use Chronicle.Events.EventType

  defstruct [:member_name]
end

defmodule MyApp.Events.ChoosingStyleBookReturned do
  use Chronicle.Events.EventType

  defstruct []
end
```
