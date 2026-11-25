```elixir
defmodule MyApp.EventSequencesSequenceNumberForObserver do
  def tail_for_observer do
    Cratis.Chronicle.EventSequences.EventLog.get_tail_sequence_number_for_observer(
      MyApp.Reactors.OrderNotifier
    )
  end
end
```
