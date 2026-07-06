```elixir
defmodule MyApp.Events.EcCqsBookCreated do
  use Chronicle.Events.EventType, id: "ec-cqs-book-created"

  defstruct [:title]
end

defmodule MyApp.ReadModels.EcCqsBook do
  defstruct id: "", title: ""
end

# Commands — fire and forget, never return projected state
defmodule MyApp.EcCqsBookCommandHandler do
  alias MyApp.Events.EcCqsBookCreated

  def create(book_id, title) do
    Chronicle.append(book_id, %EcCqsBookCreated{title: title})
  end
end

# Queries — always read from projections
defmodule MyApp.EcCqsBookQueryHandler do
  alias MyApp.ReadModels.EcCqsBook

  def get_book(book_id) do
    Chronicle.read_model(EcCqsBook, book_id)
  end
end
```
