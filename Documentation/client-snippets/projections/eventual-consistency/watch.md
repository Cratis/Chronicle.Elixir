```elixir
defmodule MyApp.Events.EcWatchBookCreated do
  use Chronicle.Events.EventType, id: "ec-watch-book-created"

  defstruct [:title, :author]
end

defmodule MyApp.ReadModels.EcWatchBookInventory do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.EcWatchBookCreated

  defstruct [:id, :title, :author]

  from EcWatchBookCreated,
    set: [id: :event_source_id, title: :title, author: :author]
end

defmodule MyApp.EcWatchBookService do
  alias Chronicle.ReadModels
  alias MyApp.Events.EcWatchBookCreated
  alias MyApp.ReadModels.EcWatchBookInventory

  # Subscribes the calling process to live changesets for every instance of
  # EcWatchBookInventory. Chronicle.ReadModels.watch/2 is Elixir's equivalent
  # of the C#/TypeScript clients' Watch<TReadModel>(): instead of an
  # IObservable, the calling process receives
  # {:chronicle_read_model_changed, EcWatchBookInventory, changeset} messages
  # until unwatch/1 is called.
  def watch_book_changes, do: ReadModels.watch(EcWatchBookInventory)

  def create_book_and_watch(title, author) do
    book_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    # Subscribe before appending so the update is observed once the
    # projection catches up.
    {:ok, watcher} = watch_book_changes()

    :ok = Chronicle.append(book_id, %EcWatchBookCreated{title: title, author: author})

    receive do
      {:chronicle_read_model_changed, EcWatchBookInventory, %{model_key: ^book_id} = changeset} ->
        IO.puts("Book projection updated: #{changeset.read_model && changeset.read_model.title}")
    after
      5_000 -> :timeout
    end

    ReadModels.unwatch(watcher)
  end
end
```
