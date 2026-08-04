```elixir
defmodule MyApp.ExternalServicesIndexRegisterHttp do
  def register_customers_api(token) do
    Chronicle.ExternalServices.register("CustomersApi", fn builder ->
      builder
      |> Chronicle.ExternalServices.DefinitionBuilder.http("https://api.example.com")
      |> Chronicle.ExternalServices.DefinitionBuilder.with_bearer_token(token)
      |> Chronicle.ExternalServices.DefinitionBuilder.with_header("X-Tenant", "acme")
    end)
  end
end
```
