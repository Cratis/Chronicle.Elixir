```elixir
defmodule MyApp.NotificationService do
  def notify_next_in_line(_book_id), do: :ok
  def notify_next_in_line(_book_id, _book_title), do: :ok
end

defmodule MyApp.Reactors.WaitlistNotifier do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.BookReturned
  alias MyApp.NotificationService

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    # book_id is the id this happened to
    NotificationService.notify_next_in_line(book_id)
    :ok
  end
end
```
