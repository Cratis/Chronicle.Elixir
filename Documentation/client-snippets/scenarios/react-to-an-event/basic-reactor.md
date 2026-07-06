```elixir
defmodule MyApp.Events.ScenariosReactBookReturned do
  use Chronicle.Events.EventType, id: "scenarios-react-book-returned"

  defstruct [:isbn]
end

defmodule MyApp.ScenariosReactNotificationService do
  def notify_next_in_line(_book_id), do: :ok
  def notify_next_in_line(_book_id, _book_title), do: :ok
end

defmodule MyApp.Reactors.ScenariosReactWaitlistNotifier do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ScenariosReactBookReturned
  alias MyApp.ScenariosReactNotificationService

  @handles ScenariosReactBookReturned

  @impl true
  def handle(%ScenariosReactBookReturned{}, context) do
    # context.event_source_id is the source the event happened to (the book)
    ScenariosReactNotificationService.notify_next_in_line(Map.get(context, :event_source_id))
    :ok
  end
end
```
