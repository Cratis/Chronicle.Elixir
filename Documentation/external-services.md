# External Services

`Chronicle.ExternalServices` provides an idiomatic Elixir API for registering external service definitions with Chronicle.

External services let the Chronicle kernel talk to systems outside the event store — an HTTP API or a MsSql/PostgreSql database — under a name other kernel features (such as captures) can reference. They are usually configured in the Workbench, but the Elixir client also exposes a programmatic API.

## Registering an HTTP service

Register an HTTP endpoint with bearer-token authentication and a custom header:

```elixir
:ok =
  Chronicle.ExternalServices.register("CustomersApi", fn builder ->
    builder
    |> Chronicle.ExternalServices.DefinitionBuilder.http("https://api.example.com")
    |> Chronicle.ExternalServices.DefinitionBuilder.with_bearer_token(token)
    |> Chronicle.ExternalServices.DefinitionBuilder.with_header("X-Tenant", "acme")
  end)
```

`configure` receives a `Chronicle.ExternalServices.DefinitionBuilder` and must return it (or a continuation of it) once the endpoint is configured.

## Registering a database service

Register a PostgreSQL database endpoint:

```elixir
:ok =
  Chronicle.ExternalServices.register("CustomersDb", fn builder ->
    Chronicle.ExternalServices.DefinitionBuilder.postgre_sql(
      builder,
      "db.example.com",
      "customers",
      "postgres",
      password,
      5432
    )
  end)
```

Use `Chronicle.ExternalServices.DefinitionBuilder.ms_sql/6` instead for a Microsoft SQL Server endpoint — it takes the same host, database, username, password, and port arguments.

## Builder API

`Chronicle.ExternalServices.DefinitionBuilder` is immutable and pipeline-friendly.

```elixir
builder
|> DefinitionBuilder.http("https://api.example.com")
|> DefinitionBuilder.with_basic_auth("user", "password")
|> DefinitionBuilder.with_bearer_token("token")
|> DefinitionBuilder.with_oauth("https://login.example.com", "client-id", "client-secret")
|> DefinitionBuilder.with_header("x-tenant", "acme")
```

- `http/2` configures an HTTP endpoint.
- `ms_sql/6` and `postgre_sql/6` configure a database endpoint — mutually exclusive with `http/2` and each other; the last call wins.
- `with_basic_auth/3`, `with_bearer_token/2`, and `with_oauth/4` are mutually exclusive with each other and only meaningful for HTTP endpoints.
- `with_header/3` adds or replaces an HTTP header sent with every request.
- `with_option/3` adds a provider-specific option to a database endpoint's connection configuration.

## Using a named client

```elixir
:ok =
  Chronicle.ExternalServices.register(
    "CustomersApi",
    fn builder -> Chronicle.ExternalServices.DefinitionBuilder.http(builder, "https://api.example.com") end,
    client: :bank_chronicle
  )
```
