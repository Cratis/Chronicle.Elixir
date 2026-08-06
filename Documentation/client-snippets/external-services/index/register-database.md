```elixir
defmodule MyApp.ExternalServicesIndexRegisterDatabase do
  def register_customers_db(password) do
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
  end
end
```
