```elixir
defmodule MyApp.ReadModels.BorrowedBook do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", member_name: ""

  # member_name travels as camelCase JSON.
  from MyApp.Events.BookBorrowed,
    set: [id: :event_source_id, member_name: "memberName"]

  removed_with MyApp.Events.BookReturned, []
end
```
