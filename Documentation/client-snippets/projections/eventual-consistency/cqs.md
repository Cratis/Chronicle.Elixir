```elixir
defmodule MyApp.Events.EcCqsBookCreated do
  use Cratis.Chronicle.Events.EventType, id: "ec-cqs-book-created"

  defstruct [:title]
end

defmodule MyApp.ReadModels.EcCqsBook do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct id: "", title: ""
end

# Commands — fire and forget, never return projected state
defmodule MyApp.EcCqsBookCommandHandler do
  alias MyApp.Events.EcCqsBookCreated

  def create(book_id, title) do
    Cratis.Chronicle.append(book_id, %EcCqsBookCreated{title: title})
  end
end

# Queries — always read from projections
defmodule MyApp.EcCqsBookQueryHandler do
  alias MyApp.ReadModels.EcCqsBook

  def get_book(book_id) do
    Cratis.Chronicle.read_model(EcCqsBook, book_id)
  end
end
```
