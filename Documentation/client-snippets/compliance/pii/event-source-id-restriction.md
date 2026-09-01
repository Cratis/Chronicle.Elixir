```elixir
# Raises ArgumentError at compile time — PII is not supported on a
# Chronicle.Concept declared with event_source_id: true.
#
# defmodule MyApp.Compliance.Pii.EmployeeId do
#   use Chronicle.Concept, type: :uuid, event_source_id: true
#   pii()
# end
```
