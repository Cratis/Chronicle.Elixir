```elixir
defmodule MyApp.Events.ConstraintsUniqueEventTypeScopedLoanCheckedOut do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-scoped-loan-checked-out"
  defstruct title: ""
end

defmodule MyApp.Events.ConstraintsUniqueEventTypeScopedLoanReturned do
  use Chronicle.Events.EventType, id: "constraints-unique-event-type-scoped-loan-returned"
  defstruct []
end

# One open loan per borrower per branch. The stream the event is appended to decides which
# cycle it belongs to, so the same borrower can hold one open loan at every branch, and
# returning at one branch opens the next cycle only there.
defmodule MyApp.Constraints.ConstraintsUniqueEventTypeOneOpenLoanPerBranch do
  use Chronicle.Events.Constraint

  unique_event_type MyApp.Events.ConstraintsUniqueEventTypeScopedLoanCheckedOut,
    name: "ConstraintsUniqueEventTypeOneOpenLoanPerBranch",
    scope: :per_event_stream_id

  removed_with MyApp.Events.ConstraintsUniqueEventTypeScopedLoanReturned
end
```
