```elixir
# Raises ArgumentError at compile time — PII is not supported on a
# Cratis.Chronicle.Concept declared with event_source_id: true.
#
# defmodule MyApp.Compliance.Pii.EmployeeId do
#   use Cratis.Chronicle.Concept, type: :uuid, event_source_id: true
#   pii()
# end
```
