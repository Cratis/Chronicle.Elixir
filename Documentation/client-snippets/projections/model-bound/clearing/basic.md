```elixir
defmodule MyApp.Events.MbClearingProjectNoted do
  use Cratis.Chronicle.Events.EventType, id: "mb-clearing-project-noted"

  defstruct [:note]
end

defmodule MyApp.Events.MbClearingProjectNoteCleared do
  use Cratis.Chronicle.Events.EventType, id: "mb-clearing-project-note-cleared"

  defstruct []
end

defmodule MyApp.ReadModels.MbClearingProject do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct project_id: nil, note: nil

  from MyApp.Events.MbClearingProjectNoted, set: [note: :note]

  clear_with MyApp.Events.MbClearingProjectNoteCleared, [:note]
end
```
