```elixir
defmodule MyApp.Events.MbClearingSetValueNullNoted do
  use Chronicle.Events.EventType, id: "mb-clearing-set-value-null-noted"

  defstruct [:note]
end

defmodule MyApp.Events.MbClearingSetValueNullCleared do
  use Chronicle.Events.EventType, id: "mb-clearing-set-value-null-cleared"

  defstruct []
end

defmodule MyApp.ReadModels.MbClearingSetValueNullProject do
  use Chronicle.ReadModels.ReadModel

  defstruct project_id: nil, note: nil

  from MyApp.Events.MbClearingSetValueNullNoted, set: [note: :note]

  # clear: [...] builds the same "$null" mapping as clear_with/2 — reach for whichever reads
  # better alongside the rest of a from/2 call's options.
  from MyApp.Events.MbClearingSetValueNullCleared, clear: [:note]
end
```
