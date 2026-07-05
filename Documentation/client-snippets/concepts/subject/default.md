```elixir
defmodule MyApp.Events.SubjectAuthorRegistered do
  use Chronicle.Events.EventType, id: "subject-author-registered"

  defstruct [:name]
end

defmodule MyApp.SubjectAuthorService do
  alias MyApp.Events.SubjectAuthorRegistered

  def register(author_id, name) do
    # Subject defaults to author_id; encryption keys for any PII on SubjectAuthorRegistered
    # are keyed by author_id.
    Chronicle.append(author_id, %SubjectAuthorRegistered{name: name})
  end
end
```
