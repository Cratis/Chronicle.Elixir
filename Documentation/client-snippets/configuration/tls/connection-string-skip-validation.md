```elixir
defmodule MyApp.TlsConnectionStringSkipValidation do
  @moduledoc false

  def connection_string do
    Cratis.Chronicle.Connections.ConnectionString.parse(
      "chronicle://localhost:35000?skipTlsValidation=true"
    )
  end
end
```
