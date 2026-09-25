```elixir
defmodule MyApp.Reactors.WaitlistNotifierWithBookTitle do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.BookReturned
  alias MyApp.NotificationService
  alias MyApp.ReadModels.Book

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    case Chronicle.read_model(Book, book_id) do
      {:ok, %Book{title: title}} ->
        NotificationService.notify_next_in_line(book_id, title)
        :ok

      # Not projected yet, or the read failed: return an error so Chronicle
      # records a failed partition you can retry.
      {:ok, nil} ->
        {:error, :book_not_projected}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```
