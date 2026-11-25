```elixir
defmodule MyApp.ExternalServicesIndexRegisterHttp do
  def register_customers_api(token) do
    Cratis.Chronicle.ExternalServices.register("CustomersApi", fn builder ->
      builder
      |> Cratis.Chronicle.ExternalServices.DefinitionBuilder.http("https://api.example.com")
      |> Cratis.Chronicle.ExternalServices.DefinitionBuilder.with_bearer_token(token)
      |> Cratis.Chronicle.ExternalServices.DefinitionBuilder.with_header("X-Tenant", "acme")
    end)
  end
end
```
