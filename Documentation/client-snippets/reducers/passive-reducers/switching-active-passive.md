```elixir
defmodule PassiveReducersSwitchableValueChanged do
  use Chronicle.Events.EventType, id: "passive-reducers-switchable-value-changed"

  defstruct [:value]
end

defmodule PassiveReducersSwitchableReadModel do
  defstruct value: 0
end

# Was active, now passive — only the `active:` option changed.
defmodule PassiveReducersSwitchableReducer do
  use Chronicle.Reducers.Reducer, model: PassiveReducersSwitchableReadModel, active: false

  alias PassiveReducersSwitchableValueChanged

  @handles PassiveReducersSwitchableValueChanged

  @impl true
  def reduce(%PassiveReducersSwitchableValueChanged{} = event, _current, _context) do
    %PassiveReducersSwitchableReadModel{value: event.value}
  end
end
```
