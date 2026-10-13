```elixir
defmodule MyApp.ReadModels.ChoosingStyleBookStatusModelBound do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, title: nil, isbn: nil, is_borrowed: false, borrowed_by: nil

  pii :borrowed_by

  from MyApp.Events.ChoosingStyleBookRegistered,
    set: [id: :event_source_id, title: :title, isbn: :isbn, is_borrowed: false],
    clear: [:borrowed_by]

  from MyApp.Events.ChoosingStyleBookBorrowed,
    set: [id: :event_source_id, is_borrowed: true, borrowed_by: :member_name]

  from MyApp.Events.ChoosingStyleBookReturned,
    set: [id: :event_source_id, is_borrowed: false],
    clear: [:borrowed_by]
end
```
