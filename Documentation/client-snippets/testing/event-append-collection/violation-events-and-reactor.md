```elixir
defmodule MyApp.Events.TestingCollectionUniqueValueRecorded do
  use Chronicle.Events.EventType, id: "testing-collection-unique-value-recorded"

  defstruct [:unique_value]
end

defmodule MyApp.Events.TestingCollectionUniqueValueFollowUp do
  use Chronicle.Events.EventType, id: "testing-collection-unique-value-follow-up"

  unique(:unique_value, name: "TestingCollectionUniqueValueFollowUp")

  defstruct [:unique_value]
end

defmodule MyApp.Reactors.TestingCollectionUniqueValueReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{TestingCollectionUniqueValueFollowUp, TestingCollectionUniqueValueRecorded}

  @handles TestingCollectionUniqueValueRecorded

  @impl true
  def handle(%TestingCollectionUniqueValueRecorded{} = event, _context),
    do: {:ok, %TestingCollectionUniqueValueFollowUp{unique_value: event.unique_value}}
end
```
