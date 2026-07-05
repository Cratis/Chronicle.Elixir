```elixir
defmodule MyApp.Events.EcBookCreated do
  use Chronicle.Events.EventType

  defstruct [:title, :author]
end

defmodule MyApp.ReadModels.EcBookInventory do
  defstruct id: "", title: "", author: ""
end

defmodule MyApp.EcBookService do
  alias MyApp.Events.EcBookCreated
  alias MyApp.ReadModels.EcBookInventory

  # Good — fire and forget: don't wait for the projection before returning
  def create_book(book_id, title, author) do
    Chronicle.append(book_id, %EcBookCreated{title: title, author: author})
    :ok
  end

  # Problematic — expecting immediate consistency
  def create_book_and_return(book_id, title, author) do
    create_book(book_id, title, author)

    # The projection may not have run yet — this can return nil or a stale instance
    Chronicle.read_model(EcBookInventory, book_id)
  end
end
```
