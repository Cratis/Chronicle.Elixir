```elixir
# Raises ArgumentError at compile time — encryption is not supported on a
# Chronicle.Concept declared with event_source_id: true.
#
# defmodule MyApp.Confidentiality.Encrypted.PartnerId do
#   use Chronicle.Concept, type: :uuid, event_source_id: true
#   encrypted()
# end
```
