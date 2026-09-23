```elixir
# One key per partner (:subject, the default).
defmodule MyApp.Confidentiality.Encrypted.PartnerApiKeyScoped do
  use Chronicle.Concept, type: :string
  encrypted()
end

# One key for every partner in the namespace.
defmodule MyApp.Confidentiality.Encrypted.PartnerWebhookSecret do
  use Chronicle.Concept, type: :string
  encrypted(:namespace)
end

# One key for the whole installation.
defmodule MyApp.Confidentiality.Encrypted.LicenseToken do
  use Chronicle.Concept, type: :string
  encrypted(:global)
end
```
