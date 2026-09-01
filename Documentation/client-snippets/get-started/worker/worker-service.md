```elixir
defmodule MyApp.GetStartedWorker do
  @moduledoc """
  Appends a book-added event once `Chronicle.Client` is running as part of
  the application's supervision tree.

  Reactors and projections keep processing events in the background for as
  long as the supervision tree stays up — there is no separate "keep running
  forever" loop to write here, unlike a .NET `BackgroundService`.
  """

  alias MyApp.Events.GetStartedBookAdded

  def add_book do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    Chronicle.append(book_id, %GetStartedBookAdded{
      title: "The Pragmatic Programmer",
      isbn: "978-0135957059"
    })
  end
end
```
