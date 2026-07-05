```elixir
defmodule MyApp.NotificationWasNotRecorded do
  defexception [:message]

  def exception(book_id) do
    %__MODULE__{message: "Notification for book #{book_id} was not recorded"}
  end
end

defmodule MyApp.Reactors.WaitlistNotifierExplicitAppend do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.BookReturned
  alias MyApp.Events.WaitlistNotificationSent
  alias MyApp.NotificationService
  alias MyApp.NotificationWasNotRecorded

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    NotificationService.notify_next_in_line(book_id)

    case Chronicle.append(book_id, %WaitlistNotificationSent{}) do
      :ok -> :ok
      {:error, _reason} -> raise NotificationWasNotRecorded, book_id
    end
  end
end
```
