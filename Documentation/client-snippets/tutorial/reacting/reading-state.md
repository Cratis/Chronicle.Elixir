```elixir
defmodule MyApp.Reactors.WaitlistNotifierWithBookTitle do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.BookReturned
  alias MyApp.NotificationService
  alias MyApp.ReadModels.Book

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    {:ok, book} = Chronicle.read_model(Book, book_id)
    NotificationService.notify_next_in_line(book_id, book.title)
    :ok
  end
end
```
