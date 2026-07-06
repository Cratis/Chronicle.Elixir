```elixir
defmodule MyApp.ReadModels.ChoosingStyleBookStatusModelBound do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", title: "", isbn: "", is_borrowed: false, borrowed_by: nil

  from MyApp.Events.ChoosingStyleBookRegistered,
    set: [id: :event_source_id, title: :title, isbn: :isbn, is_borrowed: false, borrowed_by: nil]

  from MyApp.Events.ChoosingStyleBookBorrowed,
    set: [is_borrowed: true, borrowed_by: :member_name]

  from MyApp.Events.ChoosingStyleBookReturned,
    set: [is_borrowed: false, borrowed_by: nil]
end
```
