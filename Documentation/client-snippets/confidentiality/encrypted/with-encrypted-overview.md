```elixir
defmodule MyApp.Security.SecurityOverviewPartnerApiKey do
  use Cratis.Chronicle.Concept, type: :string
  encrypted()
end

defmodule MyApp.Events.SecurityOverviewPartnerIntegrationConfigured do
  use Cratis.Chronicle.Events.EventType, id: "security-overview-partner-integration-configured"

  defstruct api_key: %MyApp.Security.SecurityOverviewPartnerApiKey{}
end
```
