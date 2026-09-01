```elixir
# Raises ArgumentError at compile time — the event source id is used to look
# up the encryption key, so it cannot itself be an encrypted value.
#
# defmodule MyApp.Compliance.Client.CustomerId do
#   use Chronicle.Concept, type: :uuid, event_source_id: true
#   pii()
# end
```
