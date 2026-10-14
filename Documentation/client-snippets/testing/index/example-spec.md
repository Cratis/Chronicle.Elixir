```elixir
defmodule MyApp.Events.TestingIndexAuthorRegistered do
  use Chronicle.Events.EventType, id: "testing-index-author-registered"

  defstruct [:name]
end

defmodule MyApp.ReadModels.TestingIndexAuthor do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.TestingIndexAuthorRegistered

  defstruct id: nil, name: nil

  from TestingIndexAuthorRegistered, set: [id: :event_source_id, name: :name]
end

defmodule MyApp.TestingIndexExampleSpecTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.TestingIndexAuthorRegistered
  alias MyApp.ReadModels.TestingIndexAuthor

  test "projecting a registered author sets the author name" do
    author_id = "author-#{System.unique_integer([:positive])}"

    {:ok, author} =
      Chronicle.Testing.Projections.apply_event(
        TestingIndexAuthor,
        nil,
        %TestingIndexAuthorRegistered{name: "Jane Austen"},
        author_id
      )

    assert author.name == "Jane Austen"
  end
end
```
