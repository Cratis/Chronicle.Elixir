```elixir
defmodule MyApp.TlsValidationEnabled do
  @moduledoc false

  def connection_string do
    Chronicle.Connections.ConnectionString.parse(
      "chronicle://my-server:35000?skipTlsValidation=false"
    )
  end
end
```
