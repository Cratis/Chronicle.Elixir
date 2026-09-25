```elixir
defmodule MyApp.ReadModels.GetStartedBorrowedBook do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", member_name: ""

  from MyApp.Events.GetStartedBookBorrowed,
    set: [id: :event_source_id, member_name: :member_name]

  removed_with MyApp.Events.GetStartedBookReturned, []
end
```
