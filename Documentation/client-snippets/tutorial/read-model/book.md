```elixir
defmodule MyApp.ReadModels.Book do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, title: nil, isbn: nil, on_loan: false, borrowed_by: nil

  from MyApp.Events.BookAdded,
    set: [id: :event_source_id, title: :title, isbn: :isbn, on_loan: false]

  from MyApp.Events.BookBorrowed,
    set: [on_loan: true, borrowed_by: :member_name]

  from MyApp.Events.BookReturned,
    set: [on_loan: false]
end
```
