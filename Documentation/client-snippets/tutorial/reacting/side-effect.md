```elixir
defmodule MyApp.WaitlistSideEffectNotificationService do
  def notify_next_in_line(_book_id), do: :ok
end

defmodule MyApp.Reactors.WaitlistNotifierSideEffect do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.BookReturned
  alias MyApp.Events.WaitlistNotificationSent
  alias MyApp.WaitlistSideEffectNotificationService, as: NotificationService

  @handles BookReturned

  @impl true
  def handle(%BookReturned{}, %{event_source_id: book_id}) do
    NotificationService.notify_next_in_line(book_id)

    # Returning {:ok, event} appends it as a side effect against the
    # triggering event source id — Chronicle appends it for you.
    {:ok, %WaitlistNotificationSent{}}
  end
end
```
