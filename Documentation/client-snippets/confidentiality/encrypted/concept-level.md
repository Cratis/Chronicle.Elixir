```elixir
defmodule MyApp.Confidentiality.Encrypted.PartnerApiKey do
  use Cratis.Chronicle.Concept, type: :string
  encrypted()
end

defmodule MyApp.Events.EncryptedAttrPartnerIntegrationConfiguredWithKey do
  use Cratis.Chronicle.Events.EventType, id: "encrypted-attr-partner-integration-configured-with-key"

  defstruct api_key: %MyApp.Confidentiality.Encrypted.PartnerApiKey{}
end
```
