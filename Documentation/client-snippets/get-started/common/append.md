```elixir
defmodule MyApp.BookService do
  alias MyApp.Events.GetStartedBookAdded

  def add_book do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    :ok =
      Chronicle.append(book_id, %GetStartedBookAdded{
        title: "The Pragmatic Programmer",
        isbn: "978-0135957059"
      })

    book_id
  end
end
```
