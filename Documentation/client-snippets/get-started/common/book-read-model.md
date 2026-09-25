```elixir
defmodule MyApp.ReadModels.GetStartedBook do
  use Chronicle.ReadModels.ReadModel

  defstruct id: "", title: "", isbn: "", on_loan: false, borrowed_by: ""

  # Event fields travel as camelCase JSON, and constants use $value(...).
  from MyApp.Events.GetStartedBookAdded,
    set: [id: :event_source_id, title: :title, isbn: :isbn, on_loan: "$value(false)"]

  from MyApp.Events.GetStartedBookBorrowed,
    set: [on_loan: "$value(true)", borrowed_by: "memberName"]

  from MyApp.Events.GetStartedBookReturned,
    set: [on_loan: "$value(false)"]
end
```
