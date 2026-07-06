```elixir
defmodule MyApp.TutorialFirstEventAppend do
  alias MyApp.Events.BookAdded

  def add_book do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    :ok =
      Chronicle.append(book_id, %BookAdded{
        title: "The Pragmatic Programmer",
        isbn: "978-0135957059"
      })

    book_id
  end
end
```
