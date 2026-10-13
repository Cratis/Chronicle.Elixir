```elixir
defmodule MyApp.ReadModels.ChoosingStyleBookStatusReducerModel do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, title: nil, isbn: nil, is_borrowed: false, borrowed_by: nil

  pii :borrowed_by
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
  def reduce(%ChoosingStyleBookRegistered{} = event, _model, context) do
    %MyApp.ReadModels.ChoosingStyleBookStatusReducerModel{
      id: context.event_source_id,
      title: event.title,
      isbn: event.isbn,
      is_borrowed: false,
      borrowed_by: nil
    }
  end

  def reduce(%ChoosingStyleBookBorrowed{} = event, model, context) do
    model = model || %MyApp.ReadModels.ChoosingStyleBookStatusReducerModel{id: context.event_source_id}
    %{model | is_borrowed: true, borrowed_by: event.member_name}
  end

  def reduce(%ChoosingStyleBookReturned{}, model, context) do
    model = model || %MyApp.ReadModels.ChoosingStyleBookStatusReducerModel{id: context.event_source_id}
    %{model | is_borrowed: false, borrowed_by: nil}
  end
end
```
