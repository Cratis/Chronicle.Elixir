```elixir
defmodule MyApp.ReadModels.ScenariosReactBook do
  defstruct [:title]
end

defmodule MyApp.Reactors.ScenariosReactWaitlistNotifierWithTitle do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ScenariosReactBookReturned
  alias MyApp.ReadModels.ScenariosReactBook
  alias MyApp.ScenariosReactNotificationService

  @handles ScenariosReactBookReturned

  @impl true
  def handle(%ScenariosReactBookReturned{}, %{event_source_id: book_id}) do
    # Strongly consistent — rebuilt from the event log, includes this event
    {:ok, book} = Chronicle.read_model(ScenariosReactBook, book_id)
    ScenariosReactNotificationService.notify_next_in_line(book_id, book.title)
    :ok
  end
end
```
