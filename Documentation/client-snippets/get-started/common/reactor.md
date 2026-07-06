```elixir
defmodule MyApp.Reactors.GetStartedBookReturnedNotifier do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.GetStartedBookReturned

  @handles GetStartedBookReturned

  @impl true
  def handle(%GetStartedBookReturned{}, %{event_source_id: book_id}) do
    # book_id is the id this happened to
    IO.puts("Book #{book_id} was returned — notify the next member in line.")
    :ok
  end
end
```
