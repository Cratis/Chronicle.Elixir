```elixir
defmodule MyApp.Events.MbClearingNullableNoted do
  use Chronicle.Events.EventType, id: "mb-clearing-nullable-noted"

  defstruct [:note]
end

defmodule MyApp.Events.MbClearingNullableCleared do
  use Chronicle.Events.EventType, id: "mb-clearing-nullable-cleared"

  defstruct []
end

defmodule MyApp.ReadModels.MbClearingNullableProject do
  use Chronicle.ReadModels.ReadModel

  # The member a clear_with/2 or clear: target names has to default to `nil`. A struct field
  # that defaults to a concrete value such as "" is not nullable to the kernel, and clearing it
  # writes the type default back instead of no value — the same ambiguity .NET's
  # CannotClearNonNullableMember check exists to prevent.
  defstruct project_id: nil, note: nil

  from MyApp.Events.MbClearingNullableNoted, set: [note: :note]

  clear_with MyApp.Events.MbClearingNullableCleared, [:note]
end
```
