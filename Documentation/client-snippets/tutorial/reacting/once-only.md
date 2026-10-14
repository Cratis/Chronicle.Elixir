```elixir
defmodule MyApp.OnceOnlyNotificationService do
  def notify_next_in_line(_book_id), do: :ok
end

defmodule MyApp.Reactors.WaitlistNotifierOnceOnly do
  # `once_only: true` is never replayed: use it for side effects such as notifications.
  use Chronicle.Reactors.Reactor, once_only: true

  alias MyApp.Events.BookReturned
  alias MyApp.OnceOnlyNotificationService

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    OnceOnlyNotificationService.notify_next_in_line(book_id)
    :ok
  end
end
```
