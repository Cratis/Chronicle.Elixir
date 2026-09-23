```elixir
defmodule MyApp.Events.EncryptedAttrPartnerIntegrationConfigured do
  use Chronicle.Events.EventType, id: "encrypted-attr-partner-integration-configured"

  defstruct [:partner_name, :api_key]

  encrypted(:api_key, :subject, "Partner API key")
end

# When this event is written, api_key is encrypted. partner_name is stored as plaintext.
```
