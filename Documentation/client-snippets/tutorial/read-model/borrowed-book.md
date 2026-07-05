```elixir
defmodule MyApp.ReadModels.BorrowedBook do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, member_name: nil

  from MyApp.Events.BookBorrowed,
    set: [id: :event_source_id, member_name: :member_name]

  removed_with MyApp.Events.BookReturned, []
end
```
