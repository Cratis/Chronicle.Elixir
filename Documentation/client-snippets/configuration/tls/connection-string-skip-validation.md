```elixir
defmodule MyApp.TlsConnectionStringSkipValidation do
  @moduledoc false

  def connection_string do
    Chronicle.Connections.ConnectionString.parse(
      "chronicle://localhost:35000?skipTlsValidation=true"
    )
  end
end
```
