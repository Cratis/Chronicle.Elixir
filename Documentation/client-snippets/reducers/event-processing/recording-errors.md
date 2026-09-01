```elixir
defmodule EventProcessingInvalidDataDetected do
  use Chronicle.Events.EventType, id: "event-processing-invalid-data-detected"

  defstruct [:reason]
end

defmodule EventProcessingValidationResult do
  defstruct is_valid: true, errors: []
end

defmodule EventProcessingValidationResultReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingValidationResult

  alias EventProcessingInvalidDataDetected

  @handles EventProcessingInvalidDataDetected

  @impl true
  def reduce(%EventProcessingInvalidDataDetected{} = event, current, _context) do
    errors = if current, do: current.errors, else: []
    %EventProcessingValidationResult{is_valid: false, errors: errors ++ [event.reason]}
  end
end
```
