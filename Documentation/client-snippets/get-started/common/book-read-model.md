```elixir
defmodule MyApp.ReadModels.GetStartedBook do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, title: nil, isbn: nil, on_loan: false, borrowed_by: nil

  from MyApp.Events.GetStartedBookAdded,
    set: [id: :event_source_id, title: :title, isbn: :isbn, on_loan: false]

  from MyApp.Events.GetStartedBookBorrowed,
    set: [on_loan: true, borrowed_by: :member_name]

  from MyApp.Events.GetStartedBookReturned,
    set: [on_loan: false]
end
```
