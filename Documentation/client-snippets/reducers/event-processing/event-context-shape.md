```elixir
defmodule EventProcessingEventContextShape do
  @moduledoc """
  Illustrative subset of the context map reduce/3 receives as its third
  argument — see Chronicle.Reducers.Reducer for the authoritative list.
  """

  # %{event_source_id: ..., sequence_number: ..., occurred: ..., observation_state: ...}
  def describe(%{
        event_source_id: event_source_id,
        sequence_number: sequence_number,
        occurred: occurred,
        observation_state: observation_state
      }) do
    {event_source_id, sequence_number, occurred, observation_state}
  end
end
```
