```elixir
defmodule MyApp.Compliance.PiiWithConcepts.LegalName do
  use Chronicle.Concept, type: :string

  pii(
    "Collected under GDPR Art. 6(1)(b) — necessary for contract performance. " <>
      "Retention: contract duration + 7 years."
  )
end
```
