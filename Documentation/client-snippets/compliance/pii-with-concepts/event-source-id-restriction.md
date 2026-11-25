```elixir
# Raises ArgumentError at compile time — any Cratis.Chronicle.Concept declared with
# event_source_id: true cannot also declare pii/0,1.
#
# defmodule MyApp.Compliance.PiiWithConcepts.EmployeeId do
#   use Cratis.Chronicle.Concept, type: :uuid, event_source_id: true
#   pii()
# end
```
