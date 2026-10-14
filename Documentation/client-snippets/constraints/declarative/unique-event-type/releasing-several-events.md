```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanCheckedOut do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-several-loan-checked-out"
  defstruct title: ""
end

defmodule MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanReturned do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-several-loan-returned"
  defstruct []
end

defmodule MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanWrittenOff do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-several-loan-written-off"
  defstruct []
end

# A loan is open until it is returned or written off. Both end the cycle, so the borrower can
# take the next loan whichever way the previous one finished.
defmodule MyApp.Constraints.ConstraintsUniqueEventTypeSeveralOneOpenLoan do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanCheckedOut,
    name: "ConstraintsUniqueEventTypeSeveralOneOpenLoan"

  removed_with MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanReturned
  removed_with MyApp.Events.ConstraintsUniqueEventTypeSeveralLoanWrittenOff
end
```
