```elixir
defmodule MyApp.ReadModels.ChoosingStyleBookStatusReducerModel do
  defstruct title: "", isbn: "", is_borrowed: false, borrowed_by: nil
end

defmodule MyApp.Reducers.ChoosingStyleBookStatusReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.ChoosingStyleBookStatusReducerModel

  alias MyApp.Events.{
    ChoosingStyleBookBorrowed,
    ChoosingStyleBookRegistered,
    ChoosingStyleBookReturned
  }

  @handles ChoosingStyleBookRegistered
  @handles ChoosingStyleBookBorrowed
  @handles ChoosingStyleBookReturned

  @impl true
  def reduce(%ChoosingStyleBookRegistered{} = event, _model, _context) do
    %MyApp.ReadModels.ChoosingStyleBookStatusReducerModel{
      title: event.title,
      isbn: event.isbn,
      is_borrowed: false,
      borrowed_by: nil
    }
  end

  def reduce(%ChoosingStyleBookBorrowed{} = event, model, _context) do
    %{model | is_borrowed: true, borrowed_by: event.member_name}
  end

  def reduce(%ChoosingStyleBookReturned{}, model, _context) do
    %{model | is_borrowed: false, borrowed_by: nil}
  end
end
```
