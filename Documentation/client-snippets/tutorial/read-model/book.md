```elixir
defmodule MyApp.ReadModels.Book do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", title: "", isbn: "", on_loan: false, borrowed_by: ""

  # Event fields travel as camelCase JSON, and constants use $value(...).
  from MyApp.Events.BookAdded,
    set: [id: :event_source_id, title: :title, isbn: :isbn, on_loan: "$value(false)"]

  from MyApp.Events.BookBorrowed,
    set: [on_loan: "$value(true)", borrowed_by: "memberName"]

  from MyApp.Events.BookReturned,
    set: [on_loan: "$value(false)"]
end
```
